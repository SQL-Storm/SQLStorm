-- {"query": "377.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1455} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (order by t.Count desc) as TagRank
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
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
        p.Title,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    inner join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    rtc.TagRank,
    rtc.TagName,
    rtc.Count as TagUseCount,
    rtc.TotalAnswers,
    rtc.TotalViews,
    ubs.DisplayName as TopUserDisplayName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TagBasedBadges,
    pa.Title as RecentPostTitle,
    pa.Score as RecentPostScore,
    pa.ViewCount as RecentPostViews,
    coalesce(dq.PostTitle, 'No Duplicate') as DuplicatePostTitle,
    coalesce(dq.RelatedPostTitle, '') as DuplicateRelatedTitle,
    coalesce(dq.LinkTypeName, '') as DuplicateLinkType,
    cq.ClosedDate,
    cq.CloseReason,
    cq.ClosedByUserName,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.LastPostDate,
    uas.FirstPostDate,
    uas.LastClosedPostDate,
    case
        when pa.Score > 0 then 'Positive'
        when pa.Score = 0 then 'Neutral'
        else 'Negative'
    end as RecentPostSentiment,
    length(coalesce(pa.Tags, '')) - length(replace(coalesce(pa.Tags, ''), '><', '')) + 1 as TagCountInPost,
    case
        when pa.Tags is null then 'No Tags'
        when pa.Tags like '%<sql>%' then 'Contains SQL Tag'
        else 'Other Tags'
    end as TagCategory,
    substring(pa.Title from 1 for 30) || '...' as ShortTitleSnippet
from RecursiveTagCounts rtc
left join UserBadgeStats ubs on ubs.UserId = (
    select OwnerUserId from Posts p2
    where p2.Tags like '%' || rtc.TagName || '%'
    order by p2.Score desc nulls last limit 1
)
left join PostActivityWindow pa on pa.OwnerUserId = ubs.UserId and pa.RecentPostRank = 1
left join DuplicateLinks dq on dq.PostId = pa.Id
left join ClosedQuestions cq on cq.PostId = pa.Id
left join UserActivitySummary uas on uas.Id = ubs.UserId
where rtc.TagRank <= 50
order by rtc.TagRank, pa.Score desc nulls last;