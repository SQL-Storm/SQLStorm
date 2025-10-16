-- {"query": "653.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1193} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.Score as QuestionScore,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerName,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.TagName is not null
),
TopTags as (
    select Id, TagName, Count, AnswerCount, QuestionScore, OwnerReputation, OwnerName
    from RecursiveTagCounts
    where rn = 1
),
PostVotesAgg as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostHistoryCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserActivityRank as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalPosts,
        count(distinct c.Id) as TotalComments,
        rank() over (order by u.Reputation desc, count(distinct p.Id) desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
DuplicatePostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u1.DisplayName as PostOwner,
        u2.DisplayName as RelatedPostOwner,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u1 on u1.Id = p1.OwnerUserId
    left join Users u2 on u2.Id = p2.OwnerUserId
    where pl.LinkTypeId = 3 -- Duplicate
)
select
    tt.TagName,
    tt.Count as TagUseCount,
    tt.AnswerCount,
    tt.QuestionScore,
    tt.OwnerName,
    tt.OwnerReputation,
    pva.UpVotes,
    pva.DownVotes,
    pva.TotalBounty,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    phci.CloseReasonId,
    phci.CloseDate,
    uar.TotalPosts,
    uar.TotalComments,
    uar.ReputationRank,
    dp.PostTitle as DuplicatePostTitle,
    dp.RelatedPostTitle as DuplicateRelatedTitle,
    dp.PostOwner as DuplicatePostOwner,
    dp.RelatedPostOwner as DuplicateRelatedOwner,
    dp.CreationDate as DuplicateLinkDate,
    concat(
        'Tag: ', coalesce(tt.TagName, 'N/A'), 
        ' | Owner: ', coalesce(tt.OwnerName, 'Unknown'),
        ' | Rep: ', coalesce(cast(tt.OwnerReputation as varchar), '0'),
        ' | Score: ', coalesce(cast(tt.QuestionScore as varchar), '0'),
        ' | UpVotes: ', coalesce(cast(pva.UpVotes as varchar), '0'),
        ' | DownVotes: ', coalesce(cast(pva.DownVotes as varchar), '0'),
        ' | Bounty: ', coalesce(cast(pva.TotalBounty as varchar), '0')
    ) as SummaryString
from TopTags tt
left join Posts p on p.Id = tt.Id
left join PostVotesAgg pva on pva.PostId = tt.Id
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join PostHistoryCloseInfo phci on phci.PostId = p.Id
left join UserActivityRank uar on uar.UserId = u.Id
left join DuplicatePostLinks dp on dp.PostId = p.Id
where tt.Count > 1000
  and (
    phci.CloseDate is null 
    or phci.CloseDate > current_date - interval '365 days'
  )
order by tt.Count desc, tt.AnswerCount desc
limit 100;