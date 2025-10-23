-- {"query": "289.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1606} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsers as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, CommentCount, TotalVotesReceived, UserRank
    from RecursiveUserActivity
    where UserRank <= 100
),
UserBadges as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges
    from Badges b
    where b.UserId in (select UserId from TopUsers)
    group by b.UserId
),
UserPostStats as (
    select 
        p.OwnerUserId as UserId,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedAnswersCount
    from Posts p
    where p.OwnerUserId in (select UserId from TopUsers)
    group by p.OwnerUserId
),
UserRecentActivity as (
    select 
        u.Id as UserId,
        max(ph.CreationDate) as LastPostHistoryDate,
        max(p.LastActivityDate) as LastPostActivityDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    where u.Id in (select UserId from TopUsers)
    group by u.Id
),
UserTagEngagement as (
    select 
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as PostsPerTag,
        sum(p.Score) as ScorePerTag
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId in (select UserId from TopUsers) and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserTopTags as (
    select distinct on (UserId) UserId, Tag, PostsPerTag, ScorePerTag
    from UserTagEngagement
    order by UserId, ScorePerTag desc, PostsPerTag desc
),
UserLinkStats as (
    select 
        p.OwnerUserId as UserId,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPosts
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.OwnerUserId in (select UserId from TopUsers)
    group by p.OwnerUserId
),
UserCloseReasons as (
    select 
        ph.UserId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.UserId in (select UserId from TopUsers)
    group by ph.UserId, crt.Name
),
UserSummary as (
    select 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.CommentCount,
        tu.TotalVotesReceived,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.DistinctBadges,
        ups.AvgQuestionScore,
        ups.AvgAnswerScore,
        ups.MaxQuestionScore,
        ups.MaxAnswerScore,
        ups.AcceptedAnswersCount,
        ura.LastPostHistoryDate,
        ura.LastPostActivityDate,
        ura.LastCommentDate,
        ura.LastVoteDate,
        ult.Tag as TopTag,
        ult.PostsPerTag as TopTagPosts,
        ult.ScorePerTag as TopTagScore,
        uls.DuplicateLinks,
        uls.LinkedPosts
    from TopUsers tu
    left join UserBadges ub on ub.UserId = tu.UserId
    left join UserPostStats ups on ups.UserId = tu.UserId
    left join UserRecentActivity ura on ura.UserId = tu.UserId
    left join UserTopTags ult on ult.UserId = tu.UserId
    left join UserLinkStats uls on uls.UserId = tu.UserId
)
select 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.CommentCount,
    us.TotalVotesReceived,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.DistinctBadges,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    us.MaxQuestionScore,
    us.MaxAnswerScore,
    us.AcceptedAnswersCount,
    us.LastPostHistoryDate,
    us.LastPostActivityDate,
    us.LastCommentDate,
    us.LastVoteDate,
    us.TopTag,
    us.TopTagPosts,
    us.TopTagScore,
    us.DuplicateLinks,
    us.LinkedPosts,
    coalesce(cr.CloseReason, 'No Close Votes') as FrequentCloseReason,
    rank() over (order by us.Reputation desc, us.TotalVotesReceived desc) as FinalRank
from UserSummary us
left join (
    select UserId, CloseReason
    from (
        select 
            UserId,
            CloseReason,
            row_number() over (partition by UserId order by CloseCount desc) as rn
        from UserCloseReasons
    ) t
    where rn = 1
) cr on cr.UserId = us.UserId
where us.Reputation > 1000
order by FinalRank
limit 50;