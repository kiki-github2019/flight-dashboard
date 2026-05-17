classdef RibbonGroup < handle
    %RIBBONGROUP  Visual grouping of ribbon buttons (with bottom title bar).
    %
    %   A group occupies a uipanel inside the parent RibbonTab grid. The
    %   panel contains:
    %     row 1 : button row (horizontal flow)
    %     row 2 : 9-px title label (the group caption)

    properties (Access = public)
        Title    char = ''
        Buttons  cell = {}    % cell of RibbonButton handles
    end

    properties (Access = public, Transient)
        Panel              % uipanel
        ButtonGrid         % uigridlayout
        TitleLabel         % uilabel
    end

    methods
        function obj = RibbonGroup(title, buttons)
            obj.Title = char(title);
            if nargin >= 2 && iscell(buttons)
                obj.Buttons = buttons;
            end
        end

        function add(obj, button)
            obj.Buttons{end+1} = button;
        end

        function build(obj, parent, adapter)
            obj.Panel = uipanel(parent, ...
                'BorderType', 'none', ...
                'BackgroundColor', [0.96 0.96 0.96]);
            outer = uigridlayout(obj.Panel, [2 1]);
            outer.RowHeight   = {'1x', 14};
            outer.ColumnWidth = {'1x'};
            outer.Padding     = [4 2 4 2];
            outer.RowSpacing  = 1;

            nBtn = numel(obj.Buttons);
            if nBtn == 0, nBtn = 1; end
            obj.ButtonGrid = uigridlayout(outer, [1 nBtn]);
            obj.ButtonGrid.RowHeight     = {'1x'};
            obj.ButtonGrid.ColumnWidth   = repmat({64}, 1, nBtn);
            obj.ButtonGrid.ColumnSpacing = 2;
            obj.ButtonGrid.Padding       = [0 0 0 0];
            obj.ButtonGrid.BackgroundColor = [0.96 0.96 0.96];

            for k = 1:numel(obj.Buttons)
                btn = obj.Buttons{k};
                if isempty(btn) || ~isvalid(btn), continue; end
                btn.build(obj.ButtonGrid, adapter);
            end

            obj.TitleLabel = uilabel(outer, ...
                'Text', obj.Title, ...
                'HorizontalAlignment', 'center', ...
                'FontSize', 9, ...
                'FontColor', [0.40 0.40 0.40]);
        end

        function delete(obj)
            for k = 1:numel(obj.Buttons)
                try
                    b = obj.Buttons{k};
                    if ~isempty(b) && isvalid(b), delete(b); end
                catch
                end
            end
            obj.Buttons = {};
            try, if ~isempty(obj.Panel) && isvalid(obj.Panel), delete(obj.Panel); end, catch, end
        end
    end
end
