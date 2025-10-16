-- {"query": "303.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1247} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.CreationDate as TagCreationDate
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    where p.PostTypeId in (1, 2)
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
ClosedQuestions as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstClosedDate,
        string_agg(distinct crt.Name, ', ') as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc nulls last) as ReputationRank
    from Users u
),
ComplexPosts as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        urs.ReputationRank,
        pls.LinkedCount,
        pls.DuplicateCount,
        cq.FirstClosedDate,
        cq.CloseReasons,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.LastBadgeDate,
        pa.RecentPostRank,
        pa.PrevScore,
        pa.NextScore,
        -- Complex string manipulation: extract first tag or 'NoTag'
        coalesce(
            nullif(
                substring(p.Tags from '<([^>]+)>'), ''
            ), 'NoTag'
        ) as FirstTag,
        -- Complex NULL logic: days since last badge or since user creation if no badges
        coalesce(
            date_part('day', now() - ua.LastBadgeDate),
            date_part('day', now() - u.CreationDate)
        ) as DaysSinceLastBadgeOrCreation
    from Posts p
    left join UserReputationRank urs on urs.Id = p.OwnerUserId
    left join PostLinkSummary pls on pls.PostId = p.Id
    left join ClosedQuestions cq on cq.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeStats ua on ua.UserId = p.OwnerUserId
    left join PostActivityWindow pa on pa.Id = p.Id
    where p.PostTypeId = 1 -- questions only
)
select
    cp.Id,
    cp.Title,
    cp.FirstTag,
    cp.Score,
    cp.ViewCount,
    cp.CreationDate,
    cp.OwnerUserId,
    cp.ReputationRank,
    cp.LinkedCount,
    cp.DuplicateCount,
    cp.FirstClosedDate,
    cp.CloseReasons,
    cp.GoldBadges,
    cp.SilverBadges,
    cp.BronzeBadges,
    cp.LastBadgeDate,
    cp.DaysSinceLastBadgeOrCreation,
    cp.RecentPostRank,
    cp.PrevScore,
    cp.NextScore,
    -- Correlated subquery: count of answers with score > question score
    (
        select count(*)
        from Posts a
        where a.ParentId = cp.Id
          and a.Score > cp.Score
    ) as AnswersWithHigherScore,
    -- Set operator example: union of tags from this question and tags from answers
    (
        select string_agg(distinct tag, ', ')
        from (
            select unnest(string_to_array(substring(cp.Tags from 2 for length(cp.Tags)-2), '><')) as tag
            union
            select unnest(string_to_array(substring(a.Tags from 2 for length(a.Tags)-2), '><')) as tag
            from Posts a
            where a.ParentId = cp.Id and a.Tags is not null
        ) combined_tags
    ) as CombinedTags
from ComplexPosts cp
where cp.Score > 5
  and (cp.FirstClosedDate is null or cp.FirstClosedDate > now() - interval '30 days')
order by cp.Score desc, cp.ViewCount desc
limit 50;