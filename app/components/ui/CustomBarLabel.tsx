import React from "react";

interface CustomBarLabelProps {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  value?: string | number;
  fill?: string;
  fontSize?: number;
  offset?: number;
}

interface CustomValueLabelProps extends CustomBarLabelProps {
  isMax?: boolean;
}

// Minimum width for label to fit inside the bar
const MIN_WIDTH_FOR_INSIDE = 40;
const PADDING = 8;

export const CustomBarLabel: React.FC<CustomBarLabelProps> = ({
  x = 0,
  y = 0,
  width = 0,
  height = 0,
  value,
  fill = "#d6e3ff",
  fontSize = 12,
  offset = PADDING,
}) => {
  // If the bar is too small, render label outside
  const isTooSmall = width < MIN_WIDTH_FOR_INSIDE;
  const labelX = isTooSmall ? x + width + offset : x + offset;
  const textAnchor = isTooSmall ? "start" : "start";

  return (
    <text
      x={labelX}
      y={y + height / 2}
      fill={fill}
      fontSize={fontSize}
      alignmentBaseline="middle"
      textAnchor={textAnchor}
      style={{ pointerEvents: "none", fontWeight: 500 }}
    >
      {value}
    </text>
  );
};

export const CustomValueLabel: React.FC<CustomValueLabelProps> = ({
  x = 0,
  y = 0,
  width = 0,
  height = 0,
  value,
  fill = "#d6e3ff",
  fontSize = 12,
  isMax = false,
  offset = PADDING,
}) => {
  // If max, put just inside the bar, else just outside
  const labelX = isMax ? x + width - offset : x + width + offset;
  const textAnchor = isMax ? "end" : "start";

  return (
    <text
      x={labelX}
      y={y + height / 2}
      fill={fill}
      fontSize={fontSize}
      alignmentBaseline="middle"
      textAnchor={textAnchor}
      style={{ pointerEvents: "none", fontWeight: 700 }}
    >
      {value}
    </text>
  );
};

export default CustomBarLabel;