-- {"query": "355.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1417} 
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
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TopPostsPerTag as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostVoteStats as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostCommentStats as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
PostWithStats as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        coalesce(pvs.UpVotes,0) as UpVotes,
        coalesce(pvs.DownVotes,0) as DownVotes,
        coalesce(pvs.Favorites,0) as Favorites,
        coalesce(pcs.CommentCount,0) as CommentCount,
        pcs.LastCommentDate
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostVoteStats pvs on pvs.PostId = p.Id
    left join PostCommentStats pcs on pcs.PostId = p.Id
    where p.PostTypeId = 1
),
RankedPosts as (
    select
        pws.*,
        rank() over (partition by pws.OwnerUserId order by pws.Score desc, pws.ViewCount desc) as UserPostRank,
        dense_rank() over (order by pws.Score desc, pws.ViewCount desc) as GlobalRank
    from PostWithStats pws
),
ClosedQuestions as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        u.DisplayName as OwnerDisplayName,
        p.Title as RelatedTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    join Posts p on p.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        coalesce(sum(bc.GoldBadges),0) as GoldBadges,
        coalesce(sum(bc.SilverBadges),0) as SilverBadges,
        coalesce(sum(bc.BronzeBadges),0) as BronzeBadges,
        max(p.CreationDate) as LastQuestionDate,
        max(a.CreationDate) as LastAnswerDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join UserBadgeCounts bc on bc.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
TopUsers as (
    select *
    from UserActivitySummary
    where TotalQuestions > 10 and Reputation > 10000
    order by Reputation desc
    limit 10
)
select
    tu.DisplayName as User,
    tu.Reputation,
    tu.TotalQuestions,
    tu.TotalAnswers,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    rp.Title as TopQuestionTitle,
    rp.Score as TopQuestionScore,
    rp.ViewCount as TopQuestionViews,
    rp.CommentCount as TopQuestionComments,
    cq.CloseReason as LastClosedReason,
    dq.RelatedPostId as DuplicateOfPostId,
    dq.RelatedTitle as DuplicateOfTitle,
    case
        when rp.LastCommentDate is null then 'No comments'
        when rp.LastCommentDate > now() - interval '30 days' then 'Active comments'
        else 'Inactive comments'
    end as CommentActivityStatus,
    concat(
        substring(rp.Title from 1 for 30),
        case when length(rp.Title) > 30 then '...' else '' end
    ) as ShortTitle,
    coalesce(rp.UpVotes,0) - coalesce(rp.DownVotes,0) as NetVotes,
    case
        when rp.Favorites > 100 then 'Highly Favorited'
        when rp.Favorites > 0 then 'Favorited'
        else 'Not Favorited'
    end as FavoriteStatus
from TopUsers tu
left join LATERAL (
    select *
    from RankedPosts rp
    where rp.OwnerUserId = tu.UserId and rp.UserPostRank = 1
    order by rp.CreationDate desc
    limit 1
) rp on true
left join ClosedQuestions cq on cq.PostId = rp.Id
left join DuplicateLinks dq on dq.PostId = rp.Id
order by tu.Reputation desc, rp.Score desc;