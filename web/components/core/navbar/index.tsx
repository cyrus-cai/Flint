import { Box, Container, Flex, HStack, Text } from '@chakra-ui/react';
import Link from 'next/link';
import { defaultPx } from 'lib/utils/default-container-px';

const ROUTES = [
  { href: "/", title: "Changelog", type: "internal-link" },
] as const;

interface NavbarProps {
  activeHref?: typeof ROUTES[number]["href"] | "/" ;
  mode?: "light" | "dark";
}

function Navbar(props: NavbarProps) {
  return (
    <>
      <Box
        w="100%"
        zIndex="overlay"
        display="block"
        position="relative"
      >
        <Flex direction="column">
          <Flex align="center" justify="space-between">
            <Flex p={4} as="a" href="/">
              <Text fontSize="2xl" fontWeight="bold">
                HyperNote
              </Text>
            </Flex>
          </Flex>
        </Flex>
      </Box>

      <Box
        w="100%"
        zIndex="overlay"
        display={["none", "none", "none", "block"]}
        position="relative"
      >
        <Container
          px={[4, 4, 12, 12, 32]}
          maxW="container.xl"
          paddingTop={["20px", "20px", "60px"]}
          paddingBottom={["20px", "20px", "60px"]}
        >
          <Flex align="center" justify="space-between">
            <Link href="/" passHref prefetch={false}>
              <Box cursor="pointer">
                <Text fontSize="2xl" fontWeight="bold">
                  HyperNote
                </Text>
              </Box>
            </Link>

            <HStack spacing={4}>
              {ROUTES.map((route) => (
                <Link key={route.href} href={route.href} passHref>
                  <Text
                    cursor="pointer"
                    fontWeight={props.activeHref === route.href ? "bold" : "normal"}
                  >
                    {route.title}
                  </Text>
                </Link>
              ))}
            </HStack>
          </Flex>
        </Container>
      </Box>
    </>
  );
}

export default Navbar;
