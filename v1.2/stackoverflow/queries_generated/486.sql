-- {"query": "486.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        coalesce(p.Score, 0) as TotalScore
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    union all
    select
        rtc.TagId,
        rtc.TagName,
        rtc.Count,
        rtc.TotalAnswers + coalesce(p2.AnswerCount, 0),
        rtc.TotalViews + coalesce(p2.ViewCount, 0),
        rtc.TotalScore + coalesce(p2.Score, 0)
    from RecursiveTagCounts rtc
    join Posts p2 on p2.Tags like concat('%<', rtc.TagName, '>%') and p2.PostTypeId = 1
    where rtc.Count < 10000
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        row_number() over (partition by u.Id order by b.Date desc) as LatestBadgeRank,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
)
select distinct
    p.Id as PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TagBasedBadges,
    coalesce(dlc.DuplicateCount, 0) as DuplicateLinks,
    coalesce(cqr.CloseReason, 'Open') as CloseReason,
    cqr.CloseDate,
    cqr.ClosedByUserName,
    paw.CommentCountWindow,
    paw.UserPostRank,
    paw.PrevScore,
    paw.NextScore,
    rtc.Count as TagGlobalCount,
    rtc.TotalAnswers as TagTotalAnswers,
    rtc.TotalViews as TagTotalViews,
    rtc.TotalScore as TagTotalScore,
    case
        when p.Score > 100 then 'High Score'
        when p.Score between 50 and 100 then 'Medium Score'
        else 'Low Score'
    end as ScoreCategory,
    case
        when p.ViewCount is null then 'No Views'
        when p.ViewCount > 10000 then 'Very Popular'
        when p.ViewCount > 1000 then 'Popular'
        else 'Less Popular'
    end as PopularityCategory,
    substring(p.Body from 1 for 100) as BodySnippet,
    case
        when p.OwnerUserId is null then 'Anonymous'
        when ua.UserId is null then 'Deleted User'
        else ua.DisplayName
    end as OwnerDisplayName,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
    (select count(*) from Comments c where c.PostId = p.Id and c.UserId = p.OwnerUserId) as OwnerCommentsCount
from Posts p
left join UserBadgeStats ua on ua.UserId = p.OwnerUserId
left join PostActivityWindow paw on paw.Id = p.Id
left join ClosedQuestionsWithReasons cqr on cqr.PostId = p.Id
left join DuplicateLinkCounts dlc on dlc.PostId = p.Id
left join RecursiveTagCounts rtc on rtc.TagName = (select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) limit 1)
where p.PostTypeId = 1
and (p.Score > 10 or p.ViewCount > 1000)
and (ua.GoldBadges > 0 or ua.SilverBadges > 5 or ua.TagBasedBadges > 3 or ua.UserId is null)
order by p.Score desc, p.ViewCount desc
limit 100;