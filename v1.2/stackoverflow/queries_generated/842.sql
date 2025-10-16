-- {"query": "842.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1603} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.Score,0) as Score,
        coalesce(p.ViewCount,0) as ViewCount,
        u.Id as OwnerUserId,
        u.Reputation as OwnerReputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
TopTagPosts as (
    select TagId, TagName, Score, ViewCount, OwnerUserId, OwnerReputation
    from RecursiveTagCounts
    where rn = 1
),
UserBadges as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(up.BadgeCount,0) as GoldBadges,
        coalesce(us.BadgeCount,0) as SilverBadges,
        coalesce(ub.BadgeCount,0) as BronzeBadges,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        max(p.Score) over (partition by u.Id) as MaxPostScore
    from Users u
    left join UserBadges up on up.UserId = u.Id and up.Class = 1
    left join UserBadges us on us.UserId = u.Id and us.Class = 2
    left join UserBadges ub on ub.UserId = u.Id and ub.Class = 3
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
PostWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rn
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId in (1,2)
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId
),
RankedPosts as (
    select *,
        lag(Score) over (partition by OwnerUserId order by Score desc) as PrevScore,
        lead(Score) over (partition by OwnerUserId order by Score desc) as NextScore
    from PostWithVotes
    where rn <= 5
),
ClosedDuplicateQuestions as (
    select
        ph.PostId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment as CloseReasonId,
        cr.Name as CloseReasonName,
        p.Title,
        t.TagName
    from PostHistory ph
    inner join CloseReasonTypes cr on cr.Id::text = ph.Comment
    inner join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
    left join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    ) t on true
    where ph.PostHistoryTypeId = 10 -- Post Closed
    and cr.Name ilike '%duplicate%'
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) as DuplicateLinkCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
    group by pl.PostId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        count(distinct vh.Id) filter (where vh.PostHistoryTypeId = 10) as TotalClosures,
        max(vh.CreationDate) as LastClosureDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotesGiven
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join PostHistory vh on vh.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.QuestionCount,
    u.AnswerCount,
    u.MaxPostScore,
    coalesce(d.DuplicateLinkCount,0) as UserDuplicatePostLinks,
    ca.TotalPosts,
    ca.TotalComments,
    ca.TotalClosures,
    ca.LastClosureDate,
    ca.TotalUpVotesGiven,
    ca.TotalDownVotesGiven,
    ttp.TagName as TopTag,
    ttp.Score as TopTagScore,
    ttp.ViewCount as TopTagViewCount,
    case when u.Location is not null then upper(u.Location) else 'UNKNOWN' end as LocationUpper,
    substring(u.AboutMe from 1 for 50) as AboutMeSnippet,
    case when u.Views > 0 then round(u.UpVotes::numeric / (nullif(u.Views,0)),4) else null end as UpVotesPerView,
    case when u.DownVotes > 0 then round(u.DownVotes::numeric / (nullif(u.Views,0)),4) else null end as DownVotesPerView,
    rp.Score as TopPostScore,
    rp.ViewCount as TopPostViewCount,
    rp.Title as TopPostTitle,
    rp.Tags as TopPostTags
from UserAggregates u
left join DuplicateLinkCounts d on d.PostId = (
    select p.Id from Posts p where p.OwnerUserId = u.Id order by p.Score desc limit 1
)
left join UserActivitySummary ca on ca.UserId = u.Id
left join TopTagPosts ttp on ttp.OwnerUserId = u.Id
left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.rn = 1
where u.QuestionCount > 5
and (u.GoldBadges + u.SilverBadges + u.BronzeBadges) > 0
order by u.Reputation desc, u.GoldBadges desc, rp.Score desc
limit 100;