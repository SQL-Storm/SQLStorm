-- {"query": "2594.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1550} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, 0 as Level, t.WikiPostId
    from Tags t
    where t.IsRequired = 1
    union all
    select t.Id, t.TagName, r.Level + 1, t.WikiPostId
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id
    where r.Level < 3
),
UserBadgeStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end), 0) as TagBasedBadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate as QuestionCreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId
),
LatestUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.LastAccessDate,
        max(coalesce(ph.CreationDate, c.CreationDate, v.CreationDate)) as LastActivity
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.LastAccessDate
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedAt,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenedAt,
        array_agg(distinct crt.Name) filter (where ph.PostHistoryTypeId = 10) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on ph.Comment::int = crt.Id and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
PostLinkCounts as (
    select
        pl.PostId,
        count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId else null end) as LinkedPostsCount,
        count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId else null end) as DuplicatePostsCount
    from PostLinks pl
    group by pl.PostId
),
UserScoreRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        row_number() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyRank
    from Users u
    where u.Reputation > 0
),
AnswerWithWindow as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRank,
        lag(a.Score) over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as PreviousAnswerScore,
        lead(a.Score) over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as NextAnswerScore
    from Posts a
    where a.PostTypeId = 2
),
CorrelatedCommentsCount as (
    select
        p.Id as PostId,
        (select count(*) from Comments c where c.PostId = p.Id and c.UserId is not null) as CommentsByRegisteredUsers,
        (select count(*) from Comments c where c.PostId = p.Id and c.UserId is null) as CommentsByAnonymousUsers
    from Posts p
    where p.PostTypeId in (1,2)
    limit 1000
)
select
    q.QuestionId,
    q.Title,
    coalesce(nullif(q.Tags, ''), '<no tags>') as TagsProcessed,
    case when q.AcceptedAnswerId is not null then 'Yes' else 'No' end as HasAcceptedAnswer,
    q.AnswerCount,
    q.TotalAnswerScore,
    q.MaxAnswerScore,
    qc.ClosedAt,
    qc.ReopenedAt,
    array_to_string(qc.CloseReasons, ', ') as CloseReasons,
    pl.LinkedPostsCount,
    pl.DuplicatePostsCount,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadgeCount,
    ubs.LastBadgeDate,
    la.LastAccessDate,
    la.LastActivity,
    us.Rank as ReputationRank,
    ans.ScoreRank as TopAnswerRank,
    ans.PreviousAnswerScore,
    ans.NextAnswerScore,
    cc.CommentsByRegisteredUsers,
    cc.CommentsByAnonymousUsers,
    substring(q.Title from 1 for 50) || '...' as TitlePreview,
    case 
        when q.ViewCount > 10000 then 'Hot'
        when q.ViewCount between 1000 and 10000 then 'Warm'
        else 'Cold'
    end as PopularityCategory
from QuestionAnswerStats q
inner join Users u on u.Id = q.OwnerUserId
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join LatestUserActivity la on la.Id = u.Id
left join QuestionCloseInfo qc on qc.PostId = q.QuestionId
left join PostLinkCounts pl on pl.PostId = q.QuestionId
left join UserScoreRanks us on us.UserId = u.Id
left join AnswerWithWindow ans on ans.QuestionId = q.QuestionId and ans.ScoreRank = 1
left join CorrelatedCommentsCount cc on cc.PostId = q.QuestionId
where (q.AnswerCount > 5 or q.Score > 10)
  and (qc.ClosedAt is null or qc.ReopenedAt > qc.ClosedAt or qc.ReopenedAt is null)
order by q.TotalAnswerScore desc, q.ViewCount desc
limit 50;