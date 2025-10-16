-- {"query": "644.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1099} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate,
        u.Id as UserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
UserBadgeStats as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId, b.Class
),
PostVoteAggregates as (
    select
        p.Id as PostId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
        count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
        sum(coalesce(v.BountyAmount,0)) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
UserActivityWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as AnswerCount,
        max(p.CreationDate) over (partition by u.Id) as LastPostDate,
        min(p.CreationDate) over (partition by u.Id) as FirstPostDate,
        row_number() over (partition by u.Id order by p.Score desc nulls last) as TopPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ClosedQuestions as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        u.DisplayName as ClosedByUser
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3
)
select
    u.DisplayName,
    u.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    pva.UpVotes,
    pva.DownVotes,
    pva.Favorites,
    pva.TotalBounty,
    cq.CloseDate,
    cq.CloseReason,
    cq.ClosedByUser,
    dl.RelatedPostId as DuplicateOfPostId,
    concat_ws(' | ',
        substring(p.Title from 1 for 50),
        coalesce(cq.CloseReason,'Open'),
        'Score:', p.Score,
        'Views:', p.ViewCount,
        'UpVotes:', pva.UpVotes,
        'DownVotes:', pva.DownVotes,
        'Favorites:', pva.Favorites
    ) as Summary,
    dense_rank() over (partition by u.Id order by p.Score desc nulls last) as UserPostRank
from Users u
left join UserActivityWindows ua on ua.UserId = u.Id
left join (
    select
        UserId,
        sum(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
        sum(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
        sum(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
    from UserBadgeStats
    group by UserId
) ub on ub.UserId = u.Id
left join Posts p on p.OwnerUserId = u.Id
left join PostVoteAggregates pva on pva.PostId = p.Id
left join ClosedQuestions cq on cq.PostId = p.Id
left join DuplicateLinks dl on dl.PostId = p.Id
where u.Reputation > 1000
  and (p.Score > 10 or p.Score is null)
  and (p.CreationDate between (current_date - interval '1 year') and current_date or p.CreationDate is null)
order by u.Reputation desc, p.Score desc nulls last
limit 100;