-- {"query": "327.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1426} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostVotesSummary as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
PostCommentsCount as (
    select
        c.PostId,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
PostCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as ReopenedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        row_number() over (order by u.Reputation desc) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3
),
CorrelatedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        (select count(*) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AnswerCount,
        (select max(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as MaxAnswerScore,
        (select avg(a.Score) from Posts a where a.ParentId = q.Id and a.PostTypeId = 2) as AvgAnswerScore
    from Posts q
    where q.PostTypeId = 1
    and q.CreationDate > current_date - interval '1 year'
)
select
    t.TagName,
    t.Count as TagCount,
    t.PostId,
    t.Score as PostScore,
    t.ViewCount as PostViews,
    t.CreationDate as PostCreationDate,
    coalesce(u.DisplayName, 'Unknown') as OwnerName,
    coalesce(u.Reputation, 0) as OwnerReputation,
    coalesce(ubs.GoldBadges, 0) as OwnerGoldBadges,
    coalesce(ubs.SilverBadges, 0) as OwnerSilverBadges,
    coalesce(ubs.BronzeBadges, 0) as OwnerBronzeBadges,
    coalesce(pvs.UpVotes, 0) as PostUpVotes,
    coalesce(pvs.DownVotes, 0) as PostDownVotes,
    coalesce(pvs.TotalBounty, 0) as PostTotalBounty,
    coalesce(pcc.CommentCount, 0) as PostCommentCount,
    pci.ClosedDate,
    pci.ReopenedDate,
    crt.QuestionId,
    crt.Title as QuestionTitle,
    crt.QuestionScore,
    crt.QuestionViews,
    crt.AnswerCount,
    crt.MaxAnswerScore,
    crt.AvgAnswerScore,
    ua.RankByReputation,
    ua.QuestionsCount,
    ua.AnswersCount,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.PostOwner as DuplicatePostOwner,
    dl.RelatedPostOwner as DuplicateRelatedPostOwner
from TopTagPosts t
left join Users u on u.Id = t.OwnerUserId
left join UserBadgeSummary ubs on ubs.UserId = t.OwnerUserId
left join PostVotesSummary pvs on pvs.PostId = t.PostId
left join PostCommentsCount pcc on pcc.PostId = t.PostId
left join PostCloseInfo pci on pci.PostId = t.PostId
left join CorrelatedAnswerStats crt on crt.QuestionId = t.PostId
left join UserActivityWindow ua on ua.Id = t.OwnerUserId
left join DuplicateLinks dl on dl.PostId = t.PostId
where
    (pci.ClosedDate is null or pci.ReopenedDate > pci.ClosedDate)
    and (t.Score > 5 or t.ViewCount > 1000)
order by t.TagName, t.Score desc, t.ViewCount desc
limit 100;