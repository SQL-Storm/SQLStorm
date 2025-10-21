-- {"query": "4058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1395} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) + coalesce(p.ViewCount, 0)/100 as PopularityScore,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    where p.PostTypeId = 1
),
RecentUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct ph.Id) as EditsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(vt.Weight) as VoteWeight,
        max(v.CreationDate) as LastVoteDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate > current_date - interval '180 days'
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > current_date - interval '180 days'
    left join Votes v on v.UserId = u.Id and v.CreationDate > current_date - interval '180 days'
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
RankedPosts as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.PostTypeId order by p.ViewCount desc, p.Score desc nulls last) as PostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.Comment, crt.Name
),
AnswersWithAcceptedFlag as (
    select
        p.Id,
        p.ParentId,
        (case when q.AcceptedAnswerId = p.Id then 1 else 0 end) as IsAccepted,
        p.Score,
        p.CreationDate,
        u.DisplayName as OwnerName
    from Posts p
    join Posts q on q.Id = p.ParentId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 2
),
ComplexPostLinkAnalysis as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkType,
        count(*) over (partition by pl.PostId) as LinkCountPerPost,
        count(*) over (partition by pl.RelatedPostId) as LinkCountPerRelatedPost,
        case when pl.LinkTypeId = 3 then 1 else 0 end as IsDuplicateLink
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AggregatedUserBadges as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        coalesce(badges.GoldBadges,0) as GoldBadges,
        coalesce(badges.SilverBadges,0) as SilverBadges,
        coalesce(badges.BronzeBadges,0) as BronzeBadges,
        coalesce(badges.TagBasedBadges,0) as TagBadges,
        rua.QuestionsCount,
        rua.AnswersCount,
        rua.EditsCount,
        rua.VoteWeight,
        u.Reputation,
        case 
            when u.LastAccessDate > current_date - interval '30 days' then 'Active'
            when u.LastAccessDate > current_date - interval '365 days' then 'Inactive'
            else 'Dormant'
        end as ActivityStatus
    from Users u
    left join AggregatedUserBadges badges on badges.UserId = u.Id
    left join RecentUserActivity rua on rua.Id = u.Id
)
select
    rp.PostTypeId,
    rp.PostRank,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    ua.DisplayName as OwnerDisplayName,
    ua.Reputation as OwnerReputation,
    ua.ActivityStatus,
    ac.IsAccepted,
    ac.Score as AnswerScore,
    ac.OwnerName as AnswerOwnerName,
    crc.CloseReasonName,
    cpl.LinkType,
    cpl.LinkCountPerPost,
    cpl.LinkCountPerRelatedPost,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TagBadges,
    rtc.TagName,
    rtc.PopularityScore
from RankedPosts rp
left join AnswersWithAcceptedFlag ac on ac.ParentId = rp.Id
left join ComplexPostLinkAnalysis cpl on cpl.PostId = rp.Id
left join CloseReasonCounts crc on crc.CloseReasonId = (
    select ph.Comment from PostHistory ph
    where ph.PostId = rp.Id and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc limit 1
)
left join UserActivitySummary ua on ua.Id = rp.OwnerUserId
left join RecursiveTagCounts rtc on rtc.TagName = (
    select unnest(string_to_array(substring(rp.Tags from 2 for length(rp.Tags)-2), '><')) limit 1
)
where rp.PostRank <= 10
order by rp.PostTypeId, rp.PostRank;