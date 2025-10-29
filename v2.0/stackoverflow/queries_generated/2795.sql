-- {"query": "2795.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1225} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        -- String expression: TagName reversed and concatenated with length of tag as text
        reverse(t.TagName) || '-' || length(t.TagName)::varchar as TagSignature
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count + rtc.Count as Count,
        reverse(t.TagName) || '-' || length(t.TagName)::varchar
    from Tags t
    join RecursiveTagCounts rtc on length(t.TagName) > length(rtc.TagName)
    where t.IsModeratorOnly = 0
),
PostsWithStats as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.OwnerUserId, -1) as OwnerUserId,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRank,
        row_number() over (partition by p.PostTypeId order by p.ViewCount desc nulls last) as ViewRank,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.FavoriteCount > 0 then 'Favorite'
            else 'Open'
        end as PostStatus
    from Posts p
),
UserBadgeAgg as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate,
        string_agg(distinct b.Name, ',' order by b.Name) as BadgeNames
    from Badges b
    group by b.UserId
),
PostLatestEdit as (
    select ph.PostId, max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- edits: title, body, tags
    group by ph.PostId
),
PostLinkCount as (
    select pl.PostId, count(distinct pl.RelatedPostId) as RelatedPostsCount
    from PostLinks pl
    group by pl.PostId
),
QuestionCloseInfo as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
ComplexStats as (
    select 
        p.Id,
        p.Title,
        p.Tags,
        COALESCE(plc.RelatedPostsCount,0) as RelatedPostsCount,
        p.Score,
        p.ViewCount,
        u.Reputation,
        uba.TotalBadges,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        COALESCE(qli.CloseReason, 'Not Closed') as CloseReason,
        ts.ScoreRank,
        ts.ViewRank,
        ts.PostStatus,
        p.CreationDate,
        ple.LastEditDate,
        -- Complex predicate and null logic: if LastEditDate is null, use CreationDate + 7 days for "EffectiveEditDate"
        coalesce(ple.LastEditDate, p.CreationDate + interval '7 days') as EffectiveEditDate,
        -- String expression: concatenating owner display name with ' - ' and PostStatus
        coalesce(u.DisplayName, '(anonymous)') || ' - ' || ts.PostStatus as OwnerStatus,
        -- Window function: rank over tags count descending, only if tags is not null
        rank() over (partition by p.PostTypeId order by (length(coalesce(p.Tags, '')) - length(replace(coalesce(p.Tags, ''), '><', '')) + 1) desc ) as TagRank,
        -- NULL logic, boolean expression: posts with no tags or closed counted as flagged
        case 
            when p.Tags is null or length(p.Tags) = 0 or p.ClosedDate is not null then 1
            else 0
        end as IsFlagged
    from PostsWithStats ts
    left join Users u on u.Id = ts.OwnerUserId
    left join UserBadgeAgg uba on uba.UserId = ts.OwnerUserId
    left join PostLatestEdit ple on ple.PostId = ts.Id
    left join PostLinkCount plc on plc.PostId = ts.Id
    left join QuestionCloseInfo qli on qli.PostId = ts.Id
    where ts.PostTypeId = 1 -- questions only
)
select
    cs.Id,
    cs.Title,
    cs.OwnerStatus,
    cs.Score,
    cs.ViewCount,
    cs.Reputation,
    cs.TotalBadges,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.RelatedPostsCount,
    cs.CloseReason,
    cs.ScoreRank,
    cs.ViewRank,
    cs.PostStatus,
    cs.CreationDate,
    cs.EffectiveEditDate,
    cs.TagRank,
    cs.IsFlagged,
    rtc.TagSignature
from ComplexStats cs
left join RecursiveTagCounts rtc
    on rtc.TagName = substring(cs.Tags from '><([^>]+)><') -- regex to extract first tag inside '<>' (if any)
where cs.IsFlagged = 0
order by cs.ScoreRank asc, cs.ViewRank asc
limit 100;