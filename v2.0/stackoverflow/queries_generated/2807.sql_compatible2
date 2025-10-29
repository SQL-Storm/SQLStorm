with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        coalesce(sum(b.Class),0) as BadgeScore,
        u.Reputation,
        u.CreationDate,
        u.Location,
        row_number() over (partition by u.Location order by u.Reputation desc, count(case when b.Class = 1 then 1 end) desc, count(case when b.Class = 2 then 1 end) desc) as LocRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Location is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), TopUsers as (
    select UserId, DisplayName, GoldBadges, SilverBadges, BronzeBadges, BadgeScore, Reputation, CreationDate, LocRank, Location
    from UserBadgeCounts
    where LocRank <= 5
), QuestionAnswerStats as (
    select
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsPosted,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersPosted,
        avg(case when p.PostTypeId in (1,2) then p.Score else null end) as AvgPostScore,
        max(case when p.PostTypeId in (1,2) then p.Score else null end) as MaxPostScore,
        min(case when p.PostTypeId in (1,2) then p.Score else null end) as MinPostScore,
        count(distinct case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then p.Id end) as QuestionsWithAcceptedAnswer
    from Posts p
    where p.OwnerUserId in (select UserId from TopUsers)
    group by p.OwnerUserId
), RecentActivity as (
    select
        ph.UserId,
        count(*) as EditCount,
        count(distinct ph.PostId) as EditedPosts,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.UserId in (select UserId from TopUsers)
      and ph.CreationDate >= (date '2024-10-01' - interval '1 year')
    group by ph.UserId
), UserComments as (
    select
        c.UserId,
        count(*) as CommentsCount,
        avg(char_length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as CommentedPosts
    from Comments c
    where c.UserId in (select UserId from TopUsers)
    group by c.UserId
), UserVotes as (
    select
        v.UserId,
        count(*) as TotalVotes,
        count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
        count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
        count(case when vt.Name = 'AcceptedByOriginator' then 1 end) as AcceptedVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId in (select UserId from TopUsers)
    group by v.UserId
), TagUsage as (
    select
        u.Id as UserId,
        t.TagName,
        count(*) as TagPostCount,
        sum(p.Score) as TagPostScoreSum
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as t(TagName)
    join Tags tg on tg.TagName = t.TagName
    where u.Id in (select UserId from TopUsers)
    group by u.Id, t.TagName
), TopTagPerUser as (
    select distinct on (UserId)
        UserId,
        TagName as FavoriteTag,
        TagPostCount,
        TagPostScoreSum
    from TagUsage
    order by UserId, TagPostCount desc, TagPostScoreSum desc
), DuplicatePosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.OwnerUserId as PostOwner,
        p2.OwnerUserId as RelatedPostOwner,
        case when pl.LinkTypeId = 3 then 'Duplicate' else 'Linked' end as LinkType
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where p1.OwnerUserId in (select UserId from TopUsers)
       or p2.OwnerUserId in (select UserId from TopUsers)
), DuplicateCounts as (
    select
        coalesce(PostOwner, RelatedPostOwner) as UserId,
        sum(case when LinkType = 'Duplicate' then 1 else 0 end) as DuplicatesInvolved
    from DuplicatePosts
    group by coalesce(PostOwner, RelatedPostOwner)
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.BadgeScore,
    tas.QuestionsPosted,
    tas.AnswersPosted,
    tas.AvgPostScore,
    tas.MaxPostScore,
    tas.MinPostScore,
    tas.QuestionsWithAcceptedAnswer,
    coalesce(ra.EditCount,0) as EditsLastYear,
    coalesce(uc.CommentsCount,0) as CommentsMade,
    coalesce(uc.AvgCommentLength,0) as AvgCommentLen,
    coalesce(uv.TotalVotes,0) as VotesCast,
    coalesce(uv.UpVotes,0) as UpVotesCast,
    coalesce(uv.DownVotes,0) as DownVotesCast,
    coalesce(uv.AcceptedVotes,0) as AcceptedVotesCast,
    ttp.FavoriteTag,
    dc.DuplicatesInvolved,
    tu.Location
from TopUsers tu
left join QuestionAnswerStats tas on tas.UserId = tu.UserId
left join RecentActivity ra on ra.UserId = tu.UserId
left join UserComments uc on uc.UserId = tu.UserId
left join UserVotes uv on uv.UserId = tu.UserId
left join TopTagPerUser ttp on ttp.UserId = tu.UserId
left join DuplicateCounts dc on dc.UserId = tu.UserId
where coalesce(tas.QuestionsPosted,0) + coalesce(tas.AnswersPosted,0) > 10
order by tu.Location, tu.Reputation desc, tu.GoldBadges desc, tu.SilverBadges desc;