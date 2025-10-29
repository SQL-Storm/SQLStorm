-- {"query": "2675.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1541} 
with RecursiveVotes as (
    select
        v.Id,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        1 as Depth
    from Votes v
    inner join Posts p on p.Id = v.PostId
    where v.VoteTypeId in (2,3) -- UpMod and DownMod
    union all
    select
        v2.Id,
        v2.PostId,
        v2.VoteTypeId,
        v2.UserId,
        v2.CreationDate,
        v2.BountyAmount,
        p2.OwnerUserId,
        p2.PostTypeId,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        rv.Depth + 1
    from Votes v2
    inner join Posts p2 on p2.Id = v2.PostId
    inner join RecursiveVotes rv on rv.UserId = v2.UserId
    where v2.CreationDate > rv.CreationDate and rv.Depth < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.TagBased = 0
    group by b.UserId, b.Class
),
UserRankAndActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes
),
PostRelations as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.PostTypeId as PostType_Source,
        p2.PostTypeId as PostType_Target
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
QuestionDetails as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.FavoriteCount,
        u.DisplayName as OwnerDisplayName,
        row_number() over (partition by p.Tags order by p.Score desc nulls last, p.ViewCount desc nulls last) as TagTopRank,
        dense_rank() over (order by p.Score desc nulls last) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
CloseReasonDistribution as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    left join PostHistoryTypes cht on cht.Id = ph.PostHistoryTypeId
    where ph.PostHistoryTypeId = 10
    group by cht.Name
),
CTE_BadgedUsers as (
    select
        ubc.UserId,
        max(case when ubc.Class = 1 then ubc.BadgeCount else 0 end) as GoldBadges,
        max(case when ubc.Class = 2 then ubc.BadgeCount else 0 end) as SilverBadges,
        max(case when ubc.Class = 3 then ubc.BadgeCount else 0 end) as BronzeBadges
    from UserBadgeCounts ubc
    group by ubc.UserId
)
select
    u.DisplayName,
    u.Location,
    coalesce(bu.GoldBadges,0) as GoldBadges,
    coalesce(bu.SilverBadges,0) as SilverBadges,
    coalesce(bu.BronzeBadges,0) as BronzeBadges,
    u.Reputation,
    u.ReputationRank,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.MaxPostScore,
    u.TotalUpVotes,
    u.TotalDownVotes,
    (u.UpVotes::float / nullif(u.DownVotes,0)) as UpDownRatio,
    q.Title as TopQuestionTitle,
    q.Score as TopQuestionScore,
    q.ViewCount as TopQuestionViewCount,
    q.TagTopRank,
    pr.LinkTypeName,
    pr.PostId,
    pr.RelatedPostId,
    crd.CloseReason,
    crd.CloseCount,
    substr(u.DisplayName || ' - ' || coalesce(u.Location,'Unknown'), 1, 40) as DisplaySummary
from UserRankAndActivity u
left join CTE_BadgedUsers bu on bu.UserId = u.UserId
left join lateral (
    select
        p.Title,
        p.Score,
        p.ViewCount,
        p.TagTopRank
    from QuestionDetails p 
    where p.OwnerUserId = u.UserId
    order by p.Score desc nulls last
    limit 1
) q on true
left join lateral (
    select pr.LinkTypeName, pr.PostId, pr.RelatedPostId
    from PostRelations pr
    where pr.PostType_Source = 1 and pr.PostId in (
        select p.Id from Posts p where p.OwnerUserId = u.UserId and p.PostTypeId = 1
    )
    order by pr.LinkTypeName nulls last, pr.PostId
    limit 1
) pr on true
left join lateral (
    select crd.CloseReason, crd.CloseCount
    from CloseReasonDistribution crd
    order by crd.CloseCount desc nulls last
    limit 1
) crd on true
where u.QuestionsAsked > 5
  and (u.Reputation > 1000 or coalesce(bu.GoldBadges,0) > 0)
  and (u.Location is not null and u.Location <> '')
order by u.ReputationRank, bu.GoldBadges desc nulls last, u.QuestionsAsked desc
limit 100;