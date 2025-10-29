-- {"query": "2908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1579} 
with RecursiveTopUsers as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over(order by u.Reputation desc) as Rank
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 500
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    union all
    select 
        rt.UserId,
        rt.DisplayName,
        rt.Reputation,
        rt.CreationDate,
        rt.TotalBadges,
        rt.GoldBadges,
        rt.SilverBadges,
        rt.BronzeBadges,
        rt.Rank + 1
    from RecursiveTopUsers rt
    where rt.Rank < 100
),
UserTopPosts as (
    select
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        COALESCE(p.Tags,'') as Tags,
        p.AnswerCount,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    where p.OwnerUserId in (select UserId from RecursiveTopUsers)
),
PostWithAcceptedAnswer as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Score as QuestionScore,
        p.ViewCount as QuestionViewCount,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        a.CreationDate as AcceptedAnswerCreationDate
    from Posts p
    left join Posts a on p.AcceptedAnswerId = a.Id
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10,12,13)) as ClosedOrDeletedPosts,
        avg(case when c.Score is not null then c.Score else 0 end) as AvgCommentScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserTagDetails as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName,
        count(*) as PostCountPerTag,
        max(p.Score) as MaxScorePerTag,
        min(p.CreationDate) as FirstPostDatePerTag,
        max(p.CreationDate) as LastPostDatePerTag
    from Posts p
    where p.OwnerUserId is not null and p.Tags is not null and p.Tags <> ''
    group by p.OwnerUserId, TagName
),
TopTags as (
    select
        utd.UserId,
        utd.TagName,
        utd.PostCountPerTag,
        utd.MaxScorePerTag,
        row_number() over (partition by utd.UserId order by utd.PostCountPerTag desc, utd.MaxScorePerTag desc) as TagRank
    from UserTagDetails utd
),
FilteredTopTags as (
    select * from TopTags where TagRank <= 3
),
DuplicatePostPairs as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pt1.Title as PostTitle,
        pt2.Title as RelatedPostTitle,
        lt.Name as LinkTypeName
    from PostLinks pl
    join Posts pt1 on pt1.Id = pl.PostId
    join Posts pt2 on pt2.Id = pl.RelatedPostId
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId IN (1,3)
),
ClosedPostDetails as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId,
        cr.Name as CloseReasonName
    from PostHistory ph
    left join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, cr.Name
)
select
    ru.Rank,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalBadges,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.ClosedOrDeletedPosts,
    coalesce(nullif(ua.AvgCommentScore,0),0) as AvgCommentScore,
    ua.TotalUpVotesReceived,
    ua.TotalDownVotesReceived,
    array_agg(distinct ftt.TagName order by ftt.TagRank) as TopTags,
    sum(utd.PostCountPerTag) as TotalPostsInTopTags,
    max(utd.MaxScorePerTag) as HighestScoreInTopTags,
    count(distinct dpp.PostId) filter (where dpp.LinkTypeName = 'Duplicate') as DuplicateLinksFromUserPosts,
    count(distinct cpd.PostId) as TimesUserPostsClosed
from RecursiveTopUsers ru
left join UserActivity ua on ua.UserId = ru.UserId
left join FilteredTopTags ftt on ftt.UserId = ru.UserId
left join UserTagDetails utd on utd.UserId = ru.UserId and utd.TagName = ftt.TagName
left join DuplicatePostPairs dpp on dpp.PostId in (select Id from Posts where OwnerUserId = ru.UserId)
left join ClosedPostDetails cpd on cpd.PostId in (select Id from Posts where OwnerUserId = ru.UserId)
group by 
    ru.Rank, ru.DisplayName, ru.Reputation, ru.TotalBadges, ru.GoldBadges, ru.SilverBadges, ru.BronzeBadges,
    ua.QuestionCount, ua.AnswerCount, ua.CommentCount, ua.ClosedOrDeletedPosts, ua.AvgCommentScore, ua.TotalUpVotesReceived, ua.TotalDownVotesReceived
order by ru.Rank
limit 100;