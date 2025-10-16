-- {"query": "182.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1521} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank
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
        p.AcceptedAnswerId,
        count(c.Id) as CommentCount,
        sum(v.VoteTypeId = 2)::int as UpVotes,
        sum(v.VoteTypeId = 3)::int as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId
),
AcceptedAnswerDetails as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
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
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopTagsWithUserCounts as (
    select
        rtc.TagName,
        rtc.Count as TagCount,
        count(distinct p.OwnerUserId) as DistinctUsersWithPosts,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore
    from RecursiveTagCounts rtc
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || rtc.TagName || '%'
    group by rtc.TagName, rtc.Count
    having count(distinct p.OwnerUserId) > 10
    order by rtc.Count desc
    limit 50
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ubs.TagBasedBadges, 0) as TagBasedBadges,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    paw.Id as RecentPostId,
    paw.Title as RecentPostTitle,
    paw.Score as RecentPostScore,
    paw.ViewCount as RecentPostViews,
    paw.CommentCount as RecentPostComments,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerScore as AcceptedAnswerScore,
    aa.AnswerOwnerName,
    aa.AnswerOwnerReputation,
    dt.PostTitle as DuplicatePostTitle,
    dt.RelatedPostTitle as DuplicateRelatedPostTitle,
    ttu.TagName as PopularTag,
    ttu.TagCount,
    ttu.DistinctUsersWithPosts,
    ttu.AvgPostScore,
    ttu.MaxPostScore,
    ttu.MinPostScore
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join UserActivitySummary uas on uas.Id = u.Id
left join PostActivityWindow paw on paw.OwnerUserId = u.Id and paw.RecentPostRank = 1
left join AcceptedAnswerDetails aa on aa.QuestionId = paw.Id
left join DuplicateLinks dt on dt.PostId = paw.Id
left join TopTagsWithUserCounts ttu on paw.Tags like '%' || ttu.TagName || '%'
where u.Reputation > 1000
  and (paW.Score > 10 or paW.ViewCount > 1000)
  and (ubs.GoldBadges > 0 or ubs.SilverBadges > 2)
order by u.Reputation desc, paw.Score desc
limit 100;