-- {"query": "804.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1371} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserBadgesCTE as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        count(*) over (partition by b.UserId) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Date desc) as LatestBadgeRank
    from Badges b
),
PostWithVotesAndLinks as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(pl.LinkedCount,0) as LinkedPostsCount
    from Posts p
    left join (
        select 
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) v on v.PostId = p.Id
    left join (
        select 
            PostId,
            count(*) filter (where LinkTypeId = 1) as LinkedCount
        from PostLinks
        group by PostId
    ) pl on pl.PostId = p.Id
),
TagExplodeCTE as (
    select
        p.PostId,
        trim(tag) as Tag
    from PostWithVotesAndLinks p,
    unnest(string_to_array(
        substring(coalesce(p.Tags,'<>'),2,length(coalesce(p.Tags,'<>')) - 2), '><'
    )) as tag
),
RankedUserPosts as (
    select 
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as ScoreRank
    from Posts p
    where p.OwnerUserId is not null
),
RecentCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        c.UserId as CommentUserId
    from Comments c
    order by c.PostId, c.CreationDate desc
),
ClosedQuestionsWithReasons as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.ClosedDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
QuestionAnswerAggregates as (
    select 
        q.Id as QuestionId,
        q.Title,
        count(a.Id) filter (where a.Score > 0) as PositiveAnswerCount,
        count(a.Id) filter (where a.Score <= 0) as NonPositiveAnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title
)
select 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalPostScore,
    coalesce(ub.BadgeCount,0) as TotalBadges,
    string_agg(distinct ub.BadgeName, ', ') filter (where ub.BadgeName is not null) as BadgeNames,
    p.ScoreRank as UserTopPostRank,
    p.Score as UserTopPostScore,
    p.ViewCount as UserTopPostViews,
    rp.CommentText as LatestCommentOnTopPost,
    cq.ClosedDate,
    cq.CloseReasonName,
    qa.PositiveAnswerCount,
    qa.NonPositiveAnswerCount,
    qa.MaxAnswerScore,
    qa.AvgAnswerScore,
    string_agg(distinct t.Tag, ', ') as UserPostTags
from RecursiveUserActivity u
left join UserBadgesCTE ub on ub.UserId = u.UserId and ub.LatestBadgeRank = 1
left join RankedUserPosts p on p.OwnerUserId = u.UserId and p.ScoreRank = 1
left join RecentCommentsPerPost rp on rp.PostId = p.PostId
left join ClosedQuestionsWithReasons cq on cq.QuestionId = p.PostId and p.PostTypeId = 1
left join QuestionAnswerAggregates qa on qa.QuestionId = p.PostId
left join TagExplodeCTE t on t.PostId = p.PostId
where u.Reputation > (select percentile_cont(0.75) within group (order by Reputation) from Users)
group by 
    u.UserId, u.DisplayName, u.Reputation, u.QuestionCount, u.AnswerCount, u.TotalPostScore,
    ub.BadgeCount, ub.BadgeName, p.ScoreRank, p.Score, p.ViewCount, rp.CommentText,
    cq.ClosedDate, cq.CloseReasonName, qa.PositiveAnswerCount, qa.NonPositiveAnswerCount, qa.MaxAnswerScore, qa.AvgAnswerScore
order by u.Reputation desc, u.UserId
limit 100;