import { useState } from "react";
import { ethers } from "ethers";

const useEthers = () => {
  const [signer, setSigner] = useState(null);

  const connect = async () => {
    if (!window.ethereum) {
      alert("No MetaMask detected, please install MetaMask!");
    }

    await window.ethereum.enable();

    const provider = new ethers.providers.Web3Provider(window.ethereum);
    const signer = provider.getSigner();
    setSigner(signer);
  };

  return { connect, signer };
};

export default useEthers;
