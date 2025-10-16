-- {"query": "811.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1255} 
with recursive TagHierarchy as (
    select Id, TagName, WikiPostId, 1 as Level, cast(TagName as varchar(1000)) as Path
    from Tags
    where WikiPostId is not null
    union all
    select t.Id, t.TagName, t.WikiPostId, th.Level + 1,
           th.Path || ' > ' || t.TagName
    from Tags t
    join TagHierarchy th on t.ExcerptPostId = th.WikiPostId
    where th.Level < 5
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadgeCount,
        rank() over (order by u.Reputation desc nulls last) as RepRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(distinct a.Id) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags
),
PostVoteAggregates as (
    select 
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBountyStarted,
        max(v.CreationDate) as LastVoteDate
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as CloseEventRank
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint) 
    where ph.PostHistoryTypeId = 10
),
UserLatestActivity as (
    select u.Id as UserId, max(p.LastActivityDate) as LatestActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
TopAnswerers as (
    select 
        a.OwnerUserId,
        count(*) as AnswerCount,
        sum(a.Score) as TotalAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId
)
select
    u.DisplayName,
    u.RepRank,
    u.Reputation,
    coalesce(bs.GoldBadges,0) as GoldBadges,
    coalesce(bs.SilverBadges,0) as SilverBadges,
    coalesce(bs.BronzeBadges,0) as BronzeBadges,
    coalesce(bs.TagBasedBadgeCount,0) as TagBasedBadgeCount,
    coalesce(ta.AnswerCount,0) as TotalAnswers,
    coalesce(ta.TotalAnswerScore,0) as TotalAnswerScore,
    coalesce(ta.AvgAnswerScore,0) as AvgAnswerScore,
    ua.LatestActivity,
    tq.Id as TopQuestionId,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    tq.AnswerCount as TopQuestionAnswerCount,
    tq.CommentCount as TopQuestionCommentCount,
    pva.UpVotes,
    pva.DownVotes,
    pva.TotalBountyStarted,
    pva.LastVoteDate,
    cq.ClosedDate,
    cq.CloseReason,
    th.Level as TagHierarchyLevel,
    th.Path as TagHierarchyPath
from Users u
left join UserBadgeStats bs on bs.UserId = u.Id
left join TopAnswerers ta on ta.OwnerUserId = u.Id
left join UserLatestActivity ua on ua.UserId = u.Id
left join TopQuestions tq on tq.OwnerUserId = u.Id and tq.UserTopQuestionRank = 1
left join PostVoteAggregates pva on pva.PostId = coalesce(tq.Id,0)
left join ClosedQuestionsWithReasons cq on cq.PostId = coalesce(tq.Id,0) and cq.CloseEventRank = 1
left join LATERAL (
    select th.*
    from TagHierarchy th
    where position(concat('<', th.TagName, '>') in coalesce(tq.Tags, '')) > 0
    order by th.Level asc
    limit 1
) th on true
where u.Reputation > 1000
order by u.Reputation desc
limit 100;