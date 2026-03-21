import React from 'react';
import { classNames } from 'lib/utils';

type FooterProps = {
  hideCTA?: boolean;
  className?: string;
};

export const Footer = ({ hideCTA = false, className = '' }: FooterProps) => {
  return (
    <div className="z-50 w-full max-w-full overflow-x-hidden overflow-y-hidden">
      <div className={classNames('flex flex-col items-center mt-[64px] lg:mt-40 font-hero', className)}>
        <div className="w-full bg-gradient-to-t from-gray-100">
          <div className="m-auto lg:px-8 flex flex-col relative py-20 items-center font-normal text-gray-700 text-sm">
            <div className="flex flex-col lg:flex-row gap-8 items-center justify-center">
              <a
                className="hover:underline"
                href="/"
              >
                Changelog
              </a>
              <a
                className="hover:underline"
                href="https://flintapp.dev/download"
              >
                Download
              </a>
            </div>
            
            <div className="mt-8 text-xs text-gray-500">
              © {new Date().getFullYear()} Flint. All rights reserved.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Footer;
