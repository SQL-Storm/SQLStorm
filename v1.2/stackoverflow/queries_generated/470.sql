-- {"query": "470.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1442} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t2.Id, t2.TagName, t2.Count, t2.ExcerptPostId, t2.WikiPostId, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id and r.Level < 2
),
UserBadgeRanks as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnswersWithOwner
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, q.AcceptedAnswerId
),
QuestionCloseInfo as (
    select ph.PostId, crt.Name as CloseReason, min(ph.CreationDate) as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
TopVoters as (
    select v.UserId, count(*) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
PostLinkSummary as (
    select pl.PostId, lt.Name as LinkType, count(*) as LinkCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId, lt.Name
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
CorrelatedComments as (
    select c.PostId, count(*) as CommentCount, max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
)
select 
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    coalesce(qci.CloseReason, 'Open') as CloseReason,
    qci.CloseDate,
    ub.DisplayName as QuestionOwner,
    ub.Reputation as OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    tv.VoteCount as OwnerVoteCount,
    tv.UpVotes as OwnerUpVotes,
    tv.DownVotes as OwnerDownVotes,
    pl.LinkType,
    pl.LinkCount,
    rc.CommentCount,
    rc.LastCommentDate,
    rc.Commenters,
    rp.ScoreRank,
    concat(
        'Tags: ',
        coalesce(qas.Tags, '<none>'),
        ' | Owner: ', coalesce(ub.DisplayName, 'unknown'),
        ' | ScoreRank: ', rp.ScoreRank::text
    ) as SummaryInfo,
    -- Window function example: rank of question by view count among questions created in same year
    rank() over (partition by extract(year from qas.QuestionCreation) order by qas.ViewCount desc) as YearlyViewRank,
    -- Complex expression with NULL logic and string manipulation
    case 
        when qas.AcceptedAnswerId is not null then 
            (select p2.Score from Posts p2 where p2.Id = qas.AcceptedAnswerId)
        else null
    end as AcceptedAnswerScore,
    -- Correlated subquery: count of distinct users who answered the question
    (select count(distinct a.OwnerUserId) from Posts a where a.ParentId = qas.QuestionId and a.PostTypeId = 2 and a.OwnerUserId is not null) as DistinctAnswerers,
    -- Set operator example: union of tags from questions and tag names from Tags table (limited)
    (select string_agg(distinct t.TagName, ', ') from Tags t where t.Count > 1000) as PopularTags
from QuestionAnswerStats qas
left join QuestionCloseInfo qci on qas.QuestionId = qci.PostId
left join Users ub on qas.OwnerUserId = ub.Id
left join UserBadgeRanks ubr on ub.Id = ubr.UserId
left join TopVoters tv on ub.Id = tv.UserId
left join PostLinkSummary pl on qas.QuestionId = pl.PostId and pl.LinkType = 'Duplicate'
left join CorrelatedComments rc on qas.QuestionId = rc.PostId
left join RankedPosts rp on qas.QuestionId = rp.Id
where qas.AnswerCount > 0
and (qci.CloseDate is null or qci.CloseDate > qas.QuestionCreation)
order by qas.QuestionScore desc, qas.ViewCount desc
limit 50;