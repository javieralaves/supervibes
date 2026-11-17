import {
  Agreement01Icon,
  Airplane01Icon,
  Award01Icon,
  Baby01Icon,
  Beach02Icon,
  Bicycle01Icon,
  Book02Icon,
  BookOpen01Icon,
  BrainIcon,
  Briefcase01Icon,
  Building03Icon,
  Camera01Icon,
  Car01Icon,
  CatIcon,
  ChartIncreaseIcon,
  ChartLineData01Icon,
  ChefHatIcon,
  CodeIcon,
  Coffee01Icon,
  Coins01Icon,
  Compass01Icon,
  CrownIcon,
  Dumbbell01Icon,
  Edit02Icon,
  FavouriteIcon,
  Flag02Icon,
  GiftIcon,
  Globe02Icon,
  HeartCheckIcon,
  Home01Icon,
  Idea01Icon,
  JusticeScale01Icon,
  LanguageSkillIcon,
  LaptopIcon,
  Layers01Icon,
  Leaf01Icon,
  MagicWand01Icon,
  MapsLocation01Icon,
  Medicine01Icon,
  Megaphone01Icon,
  Message01Icon,
  Money03Icon,
  Moon02Icon,
  Mortarboard01Icon,
  MountainIcon,
  MusicNote01Icon,
  PaintBoardIcon,
  PartyIcon,
  PenTool01Icon,
  PiggyBankIcon,
  Plant01Icon,
  Presentation01Icon,
  Rocket01Icon,
  RunningShoesIcon,
  SaleTag01Icon,
  Sofa01Icon,
  SparklesIcon,
  SwimmingIcon,
  Target02Icon,
  Task01Icon,
  TentIcon,
  UserGroupIcon,
  Video01Icon,
  VoteIcon,
  Wallet01Icon,
  YogaIcon,
} from "@hugeicons/core-free-icons";
import type { IconSvgElement } from "@hugeicons/react";

export type GoalIconDef = {
  icon: IconSvgElement;
  label: string;
  keywords: string;
};

/**
 * The icons a goal can use, grouped for the picker. Goals store the key
 * (e.g. "Rocket01Icon"), so add freely, but don't remove keys that may be in use.
 */
export const GOAL_ICON_GROUPS = [
  {
    label: "Ambition",
    icons: {
      Rocket01Icon: { icon: Rocket01Icon, label: "Rocket", keywords: "launch ship startup grow" },
      Target02Icon: { icon: Target02Icon, label: "Target", keywords: "goal aim focus" },
      Flag02Icon: { icon: Flag02Icon, label: "Flag", keywords: "milestone finish" },
      Award01Icon: { icon: Award01Icon, label: "Award", keywords: "win prize achievement" },
      CrownIcon: { icon: CrownIcon, label: "Crown", keywords: "best lead world-class" },
      SparklesIcon: { icon: SparklesIcon, label: "Sparkles", keywords: "magic delight quality vibe" },
      Idea01Icon: { icon: Idea01Icon, label: "Idea", keywords: "lightbulb think" },
      MountainIcon: { icon: MountainIcon, label: "Mountain", keywords: "climb summit challenge" },
    },
  },
  {
    label: "Work",
    icons: {
      Briefcase01Icon: { icon: Briefcase01Icon, label: "Briefcase", keywords: "job career business" },
      Task01Icon: { icon: Task01Icon, label: "Tasks", keywords: "todo checklist plan" },
      ChartIncreaseIcon: { icon: ChartIncreaseIcon, label: "Growth", keywords: "chart up metrics" },
      Presentation01Icon: { icon: Presentation01Icon, label: "Presentation", keywords: "talk pitch slides" },
      Building03Icon: { icon: Building03Icon, label: "Company", keywords: "office building org" },
      Agreement01Icon: { icon: Agreement01Icon, label: "Deal", keywords: "handshake partner contract" },
      LaptopIcon: { icon: LaptopIcon, label: "Laptop", keywords: "computer remote" },
      CodeIcon: { icon: CodeIcon, label: "Code", keywords: "programming dev software" },
    },
  },
  {
    label: "Create",
    icons: {
      PaintBoardIcon: { icon: PaintBoardIcon, label: "Paint", keywords: "art design colour" },
      PenTool01Icon: { icon: PenTool01Icon, label: "Design", keywords: "vector draw" },
      Edit02Icon: { icon: Edit02Icon, label: "Write", keywords: "pencil blog essay" },
      Book02Icon: { icon: Book02Icon, label: "Book", keywords: "write author publish" },
      Camera01Icon: { icon: Camera01Icon, label: "Photo", keywords: "camera photography" },
      Video01Icon: { icon: Video01Icon, label: "Video", keywords: "film youtube" },
      MusicNote01Icon: { icon: MusicNote01Icon, label: "Music", keywords: "song instrument" },
      MagicWand01Icon: { icon: MagicWand01Icon, label: "Magic", keywords: "craft polish" },
      Layers01Icon: { icon: Layers01Icon, label: "Layers", keywords: "product stack system" },
    },
  },
  {
    label: "Cause",
    icons: {
      Megaphone01Icon: { icon: Megaphone01Icon, label: "Megaphone", keywords: "campaign voice announce" },
      VoteIcon: { icon: VoteIcon, label: "Vote", keywords: "election politics ballot" },
      JusticeScale01Icon: { icon: JusticeScale01Icon, label: "Justice", keywords: "law policy fair politics" },
      Globe02Icon: { icon: Globe02Icon, label: "World", keywords: "global planet impact" },
      UserGroupIcon: { icon: UserGroupIcon, label: "Community", keywords: "people team group" },
      Message01Icon: { icon: Message01Icon, label: "Conversation", keywords: "chat talk message" },
    },
  },
  {
    label: "Health",
    icons: {
      Dumbbell01Icon: { icon: Dumbbell01Icon, label: "Strength", keywords: "gym weights fitness" },
      RunningShoesIcon: { icon: RunningShoesIcon, label: "Running", keywords: "run marathon cardio" },
      Bicycle01Icon: { icon: Bicycle01Icon, label: "Cycling", keywords: "bike ride" },
      SwimmingIcon: { icon: SwimmingIcon, label: "Swimming", keywords: "swim pool" },
      YogaIcon: { icon: YogaIcon, label: "Yoga", keywords: "stretch mindful" },
      HeartCheckIcon: { icon: HeartCheckIcon, label: "Heart", keywords: "health wellbeing" },
      BrainIcon: { icon: BrainIcon, label: "Mind", keywords: "mental focus meditate" },
      Moon02Icon: { icon: Moon02Icon, label: "Sleep", keywords: "rest night" },
      Medicine01Icon: { icon: Medicine01Icon, label: "Medicine", keywords: "doctor care" },
      Leaf01Icon: { icon: Leaf01Icon, label: "Nature", keywords: "green eat healthy" },
    },
  },
  {
    label: "Learn",
    icons: {
      Mortarboard01Icon: { icon: Mortarboard01Icon, label: "Study", keywords: "degree school graduate" },
      BookOpen01Icon: { icon: BookOpen01Icon, label: "Read", keywords: "reading books" },
      LanguageSkillIcon: { icon: LanguageSkillIcon, label: "Language", keywords: "speak learn" },
    },
  },
  {
    label: "Money",
    icons: {
      PiggyBankIcon: { icon: PiggyBankIcon, label: "Savings", keywords: "save money" },
      Money03Icon: { icon: Money03Icon, label: "Money", keywords: "cash income" },
      Wallet01Icon: { icon: Wallet01Icon, label: "Wallet", keywords: "budget spend" },
      Coins01Icon: { icon: Coins01Icon, label: "Coins", keywords: "invest wealth" },
      ChartLineData01Icon: { icon: ChartLineData01Icon, label: "Investing", keywords: "stocks portfolio" },
      SaleTag01Icon: { icon: SaleTag01Icon, label: "Sell", keywords: "price shop" },
    },
  },
  {
    label: "Life",
    icons: {
      Home01Icon: { icon: Home01Icon, label: "Home", keywords: "house family" },
      FavouriteIcon: { icon: FavouriteIcon, label: "Love", keywords: "heart relationship" },
      Baby01Icon: { icon: Baby01Icon, label: "Family", keywords: "kids parent baby" },
      CatIcon: { icon: CatIcon, label: "Pets", keywords: "cat dog animal" },
      Plant01Icon: { icon: Plant01Icon, label: "Garden", keywords: "plant grow" },
      Sofa01Icon: { icon: Sofa01Icon, label: "Rest", keywords: "relax home" },
      Coffee01Icon: { icon: Coffee01Icon, label: "Coffee", keywords: "morning routine" },
      ChefHatIcon: { icon: ChefHatIcon, label: "Cooking", keywords: "chef food recipe" },
      GiftIcon: { icon: GiftIcon, label: "Gift", keywords: "give present" },
      PartyIcon: { icon: PartyIcon, label: "Celebrate", keywords: "party friends fun" },
    },
  },
  {
    label: "Travel",
    icons: {
      Airplane01Icon: { icon: Airplane01Icon, label: "Flight", keywords: "plane trip travel" },
      Compass01Icon: { icon: Compass01Icon, label: "Explore", keywords: "adventure direction" },
      MapsLocation01Icon: { icon: MapsLocation01Icon, label: "Map", keywords: "place location" },
      Beach02Icon: { icon: Beach02Icon, label: "Beach", keywords: "holiday summer" },
      TentIcon: { icon: TentIcon, label: "Camping", keywords: "outdoors tent" },
      Car01Icon: { icon: Car01Icon, label: "Road trip", keywords: "car drive" },
    },
  },
] as const satisfies readonly { label: string; icons: Record<string, GoalIconDef> }[];

// Distribute over the groups so we get every icon key, not just keys shared by all groups.
type KeysOf<T> = T extends unknown ? keyof T : never;
export type GoalIconName = KeysOf<(typeof GOAL_ICON_GROUPS)[number]["icons"]>;

export const GOAL_ICONS = Object.fromEntries(
  GOAL_ICON_GROUPS.flatMap((g) => Object.entries(g.icons)),
) as Record<GoalIconName, GoalIconDef>;

export const GOAL_ICON_NAMES = Object.keys(GOAL_ICONS) as [GoalIconName, ...GoalIconName[]];

export const DEFAULT_GOAL_ICON: GoalIconName = "Target02Icon";

export function isGoalIcon(value: string): value is GoalIconName {
  return value in GOAL_ICONS;
}

/** The icon for a stored name, or the default if the name is unknown. */
export function goalIcon(name: string): IconSvgElement {
  return GOAL_ICONS[isGoalIcon(name) ? name : DEFAULT_GOAL_ICON].icon;
}
