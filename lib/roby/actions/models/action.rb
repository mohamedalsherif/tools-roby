module Roby
    module Actions
        module Models
        # Basic description of an action
        class Action
            # Structure that stores the information about planning method arguments
            #
            # See MethodDescription
            Argument = Struct.new :name, :doc, :required, :default do
                def pretty_print(pp)
                    pp.text "#{name}: #{doc} (#{if required then 'required' else 'optional' end})"
                end
            end

            # The action interface on which this action is defined
            attr_accessor :action_interface_model

            # The action name
            attr_accessor :name
            # The action description
            attr_accessor :doc
            # The description of the action arguments
            #
            # @return [Array<Argument>]
            attr_reader :arguments
            # If true, the method is flagged as advanced. I.e., it won't be
            # listed by default in the shell when the 'actions' command is
            # called
            attr_predicate :advanced?
            # The return type for this method, as a task or task service model.
            # It is Roby::Task by default
            #
            # @return [Model<Roby::Task>,Model<Roby::TaskService>]
            attr_reader :returned_type

            # @return [Action] an action using this action model and the given
            #   arguments
            def new(arguments = Hash.new)
                Actions::Action.new(self, arguments)
            end

            # Task model that can be used to represent this action in a plan
            def returned_task_type
                if @returned_task_type
                    return @returned_task_type
                end

                if returned_type.kind_of?(Roby::Models::TaskServiceModel)
                    model = Class.new(Roby::Task)
                    model.provides m.returned_type
                    @returned_task_type = model
                else
                    # Create an abstract task which will be planned
                    @returned_task_type = returned_type
                end
            end

            def initialize(action_interface_model = nil, doc = nil)
                @action_interface_model = action_interface_model
                @doc = doc
                @arguments = []
                @returned_type = Roby::Task
            end

            # Documents a new required argument to the method
            def required_arg(name, doc = nil)
                arguments << Argument.new(name.to_s, doc, true)
                self
            end
            # Documents a new optional argument to the method
            def optional_arg(name, doc = nil, default = nil)
                arg = Argument.new(name.to_s, doc, false)
                arg.default = default
                arguments << arg
                self
            end
            # Sets the advanced flag to true. See #advanced?
            def advanced
                @advanced = true 
                self
            end
            # Sets the type of task returned by the action
            def returns(type)
                if !type.kind_of?(Class) && !type.kind_of?(TaskServiceModel)
                    raise ArgumentError, "#{type} is neither a task model nor a task service model"
                elsif type.kind_of?(Class) && !(type <= Roby::Task)
                    raise ArgumentError, "#{type} is neither a task model nor a task service model"
                end
                @returned_type = type
                self
            end

            # Instanciate this action on the given plan
            def instanciate(plan, arguments = Hash.new)
                run(action_interface_model.new(plan), arguments)
            end

            # Executes the action on the given action interface
            def run(action_interface, arguments = Hash.new)
                if self.arguments.empty?
                    if !arguments.empty?
                        raise ArgumentError, "#{name} expects no arguments, but #{arguments.size} are given"
                    end
                    action_interface.send(name).as_plan
                else
                    default_arguments = self.arguments.inject(Hash.new) do |h, arg|
                        h[arg.name] = arg.default
                        h
                    end
                    arguments = Kernel.validate_options arguments, default_arguments
                    self.arguments.each do |arg|
                        if arg.required && !arguments.has_key?(arg.name.to_sym)
                            raise ArgumentError, "required argument #{arg.name} not given to #{name}"
                        end
                    end
                    action_interface.send(name, arguments).as_plan
                end
            end

            def rebind(action_interface_model)
                m = dup
                m.action_interface_model = action_interface_model
                m
            end

            # Returns the plan pattern that will deploy this action on the plan
            def plan_pattern(arguments = Hash.new)
                planner = Roby::Actions::Task.new(
                    :action_interface_model => action_interface_model,
                    :action_model => self,
                    :action_arguments => arguments)
                planner.planned_task
            end

            def droby_dump(dest)
                dump = self.dup
                dump.droby_dump!(dest)
                dump
            end

            def droby_dump!(dest)
                @action_interface_model = action_interface_model.droby_dump(dest)
                @returned_type = returned_type.droby_dump(dest)
                @returned_task_type = nil
            end

            def proxy(peer)
                interface_model = action_interface_model.proxy(peer)
                if interface_model.respond_to?(:find_action_by_name) && (action = interface_model.find_action_by_name(name))
                    return action
                end

                result = self.dup
                result.proxy!(peer, interface_model)
                result
            end

            def proxy!(peer, interface_model)
                @action_interface_model = interface_model
                @returned_type = returned_type.proxy(peer)
            end

            def to_s
                "#{action_interface_model.name}.#{name}"
            end

            def pretty_print(pp)
                pp.text "Action #{name} defined on #{action_interface_model.name}"
                pp.nest(2) do
                    pp.breakable
                    pp.text "Returns "
                    returned_type.pretty_print(pp)
                    pp.breakable
                    if arguments.empty?
                        pp.text "No arguments."
                    else
                        pp.text "Arguments:"
                        pp.nest(2) do
                            pp.seplist(arguments.sort_by(&:name)) do |arg|
                                pp.breakable
                                arg.pretty_print(pp)
                            end
                        end
                    end
                end
            end
        end
        end
    end
end
