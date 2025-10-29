with recursive TagHierarchy as (
    select
        t.Id,
        t.TagName,
        coalesce(t.Count, 0) as TagCount,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = false
    union all
    select
        t.Id,
        t.TagName,
        coalesce(t.Count, 0),
        th.Level + 1,
        th.Path || cast(array[t.Id] as integer[])
    from Tags t
    join TagHierarchy th on array_length(th.Path, 1) < 3 and t.Id != all(th.Path)
    where t.IsModeratorOnly = false
),
PostScores AS (
    select 
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.PostTypeId,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        (coalesce(p.Score,0) * 0.7 + coalesce(p.ViewCount,0) * 0.2 + coalesce((select count(*) from Comments c where c.PostId = p.Id),0) * 0.1) * 
        case when p.PostTypeId = 1 then 1.5 else 1 end as WeightedScore
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate >= cast('2024-10-01' as date) - interval '180 days'
),
RankedPosts AS (
    select 
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.OwnerName,
        ps.CreationDate,
        ps.Score,
        ps.ViewCount,
        ps.WeightedScore,
        row_number() over (partition by ps.PostTypeId order by ps.WeightedScore desc) as rn,
        rank() over (partition by ps.PostTypeId order by ps.WeightedScore desc) as rnk,
        dense_rank() over (partition by ps.PostTypeId order by ps.WeightedScore desc) as dense_rnk,
        lag(ps.WeightedScore) over (partition by ps.PostTypeId order by ps.WeightedScore desc) as PrevScore,
        lead(ps.WeightedScore) over (partition by ps.PostTypeId order by ps.WeightedScore desc) as NextScore
    from PostScores ps
),
AcceptedAnswers AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        u.DisplayName as AnswererName,
        u.Reputation as AnswererReputation
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionsWithAccepted AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        aa.AnswerId,
        aa.AnswerScore,
        aa.AnswererName,
        aa.AnswererReputation
    from Posts q
    left join AcceptedAnswers aa on q.AcceptedAnswerId = aa.AnswerId
    where q.PostTypeId = 1
),
CloseReasonsSummary AS (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        min(ph.CreationDate) as FirstCloseDate,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UsersBadgeStats AS (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
HighImpactPosts AS (
    select
        rp.PostId,
        rp.Title,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.OwnerName,
        rp.CreationDate,
        rp.WeightedScore,
        qs.AnswerId,
        qs.AnswerScore,
        qs.AnswererName,
        qs.AnswererReputation,
        crs.CloseReasonName,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.TotalBadges
    from RankedPosts rp
    left join QuestionsWithAccepted qs on rp.PostId = qs.QuestionId and rp.PostTypeId = 1
    left join CloseReasonsSummary crs on crs.PostId = rp.PostId
    left join UsersBadgeStats us on us.UserId = rp.OwnerUserId
    where rp.rn <= 50
)
select
    hip.PostId,
    hip.Title,
    hip.PostTypeId,
    hip.OwnerUserId,
    hip.OwnerName,
    hip.CreationDate,
    hip.WeightedScore,
    hip.AnswerId,
    hip.AnswerScore,
    hip.AnswererName,
    hip.AnswererReputation,
    hip.CloseReasonName,
    hip.GoldBadges,
    hip.SilverBadges,
    hip.BronzeBadges,
    hip.TotalBadges,
    case 
        when hip.PostTypeId = 1 and posts.Tags is not null then concat_ws(' | ', hip.OwnerName, substring(posts.Tags from 2 for char_length(posts.Tags)-2))
        else coalesce(hip.OwnerName, 'Unknown')
    end as OwnerAndTags,
    case 
        when hip.WeightedScore > 500 then 'High'
        when hip.WeightedScore >= 100 and hip.WeightedScore <= 500 then 'Medium'
        else 'Low'
    end as ImpactLevel
from HighImpactPosts hip
left join Posts posts on posts.Id = hip.PostId
order by hip.PostTypeId, hip.WeightedScore desc
limit 100;