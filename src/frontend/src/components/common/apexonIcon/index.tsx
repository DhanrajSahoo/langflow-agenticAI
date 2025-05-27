import React from "react";
import ApexonLogo from "../../../assets/Apexon_Logo_nobg.png";

interface ApexonIconProps {
  className?: string;
}

export const ApexonIcon: React.FC<ApexonIconProps> = ({ className }) => {
  return (
    <img
      src={ApexonLogo}
      alt="Apexon Logo"
      className={className}
    />
  );
};

export default ApexonIcon; 