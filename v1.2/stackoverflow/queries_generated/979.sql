-- {"query": "979.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1716} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(u.Reputation, 0) as OwnerMaxReputation,
        row_number() over (partition by t.Id order by coalesce(u.Reputation, 0) desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
TopTagOwners as (
    select
        TagId,
        TagName,
        Count,
        AnswerCount,
        ViewCount,
        OwnerMaxReputation
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserRecentActivity as (
    select
        u.Id,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentDate,
        max(ph.CreationDate) as LastPostHistoryDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
),
TopAnsweredQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Score as QuestionScore,
        p.ViewCount,
        p.OwnerUserId,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.AcceptedAnswerId, 0) as AcceptedAnswerId
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount, max(AcceptedAnswerId) as AcceptedAnswerId
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = p.Id
    where p.PostTypeId = 1
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        row_number() over (partition by a.ParentId order by a.Score desc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
AnswersWithAcceptedFlag as (
    select
        ar.AnswerId,
        ar.QuestionId,
        ar.AnswerScore,
        case when ar.AnswerId = q.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from AnswerRanks ar
    join TopAnsweredQuestions q on q.QuestionId = ar.QuestionId
),
UserVoteSummary as (
    select
        v.UserId,
        vt.Name as VoteTypeName,
        count(*) as VotesCast,
        sum(v.BountyAmount) filter (where v.BountyAmount is not null) as TotalBountyGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId, vt.Name
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        count(*) over (partition by pl.PostId) as TotalLinksForPost
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
-- Recursive CTE to find linked posts up to 3 levels deep
RecursiveLinkedPosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        1 as Level
    from PostLinks pl
    union all
    select
        rlp.PostId,
        pl.RelatedPostId,
        rlp.Level + 1
    from RecursiveLinkedPosts rlp
    join PostLinks pl on pl.PostId = rlp.RelatedPostId
    where rlp.Level < 3
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        count(*) over (partition by u.Id order by ph.CreationDate range between interval '30 days' preceding and current row) as Activity30DayWindow,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as RecentActivityRank
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    where ph.CreationDate is not null
),
-- Set operator example combining users who have badges or high reputation
BadgeOrTopUser as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        'BadgeHolder' as UserCategory
    from Users u
    join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    union
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        'HighReputationUser' as UserCategory
    from Users u
    where u.Reputation > 10000
)
select distinct
    tto.TagName,
    tto.Count as TagUseCount,
    tto.AnswerCount,
    tto.ViewCount,
    tto.OwnerMaxReputation as OwnerTopReputation,
    u.DisplayName as OwnerDisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.LastPostActivity,
    ua.LastCommentDate,
    ua.LastPostHistoryDate,
    q.Title as TopQuestionTitle,
    q.Score as TopQuestionScore,
    q.ViewCount as TopQuestionViews,
    a.AnswerId as TopAnswerId,
    a.AnswerScore as TopAnswerScore,
    a.IsAccepted as TopAnswerIsAccepted,
    uv.VoteTypeName,
    uv.VotesCast,
    coalesce(uv.TotalBountyGiven, 0) as TotalBountyGiven,
    pl.LinkTypeName,
    pl.TotalLinksForPost,
    rlp.Level as LinkDepth,
    uaw.Activity30DayWindow,
    uaw.RecentActivityRank,
    bun.UserCategory
from TopTagOwners tto
left join Users u on u.Reputation = tto.OwnerMaxReputation and u.Id in (
    select OwnerUserId from Posts where Tags like concat('%<', tto.TagName, '>%') limit 1
)
left join UserBadgeStats ub on ub.UserId = u.Id
left join UserRecentActivity ua on ua.Id = u.Id
left join TopAnsweredQuestions q on q.OwnerUserId = u.Id
left join AnswersWithAcceptedFlag a on a.QuestionId = q.QuestionId
left join UserVoteSummary uv on uv.UserId = u.Id
left join PostLinkDetails pl on pl.PostId = q.QuestionId
left join RecursiveLinkedPosts rlp on rlp.PostId = q.QuestionId and rlp.RelatedPostId = pl.RelatedPostId
left join UserActivityWindow uaw on uaw.UserId = u.Id and uaw.RecentActivityRank = 1
left join BadgeOrTopUser bun on bun.Id = u.Id
where tto.Count > 100
  and (a.AnswerScore > 10 or a.IsAccepted = 1)
  and (uv.VoteTypeName is null or uv.VotesCast > 5)
  and (uaw.Activity30DayWindow is null or uaw.Activity30DayWindow > 3)
order by tto.Count desc, q.Score desc, a.AnswerScore desc
limit 100;