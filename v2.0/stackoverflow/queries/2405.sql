-- {"query": "2405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1454}
with Recents as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
        count(*) over (partition by p.OwnerUserId) as UserPostCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.CreationDate > cast('2024-10-01' as date) - interval '180 days'
      and p.Score is not null
),
TopPosts as (
    select * from Recents where rn <= 100
),
AcceptedAnswers as (
    select 
        a.Id,
        a.ParentId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        u.DisplayName as AnswerOwner,
        u.Reputation as AnswererRep
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
UserBadges as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
CommentStats as (
    select 
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
DuplicateLinks as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
PostEditInfo as (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 4 then ph.CreationDate end) as LastTitleEdit,
        max(case when ph.PostHistoryTypeId = 5 then ph.CreationDate end) as LastBodyEdit,
        count(distinct case when ph.PostHistoryTypeId in (4,5,6) then ph.Id end) as EditCount
    from PostHistory ph
    group by ph.PostId
),
EngagementScores as (
    select 
        p.Id,
        (coalesce(p.Score,0) * 3
        + coalesce(c.CommentCount,0) * 2
        + coalesce(dl.DuplicateCount, 0) * 5
        + coalesce(b.GoldBadges,0) * 10
        + coalesce(b.SilverBadges,0) * 5
        + coalesce(b.BronzeBadges,0) * 2
        ) as EngagementScore
    from Posts p
    left join CommentStats c on p.Id = c.PostId
    left join DuplicateLinks dl on p.Id = dl.PostId
    left join UserBadges b on p.OwnerUserId = b.UserId
),
RankedAnswers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.AnswerScore,
        a.AnswerCreation,
        a.AnswerOwner,
        a.AnswererRep,
        rank() over (partition by a.ParentId order by a.AnswerScore desc, a.AnswerCreation asc) as AnswerRank
    from AcceptedAnswers a
),
CorrelatedComments as (
    select 
        p.Id as PostId,
        (
            select count(*)
            from Comments c2 
            where c2.PostId = p.Id
            and c2.CreationDate > p.CreationDate
        ) as CommentsAfterPostDate
    from Posts p
    where exists (
        select 1 from Comments c1 where c1.PostId = p.Id
    )
)
select 
    tp.Id as PostId,
    tp.PostTypeId,
    tp.OwnerUserId,
    tp.OwnerName,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    coalesce(tp.AcceptedAnswerId, 0) as AcceptedAnswerId,
    ba.AnswerId as TopAnswerId,
    ba.AnswerScore as TopAnswerScore,
    ba.AnswerOwner as TopAnswerOwner,
    ba.AnswererRep as TopAnswererRep,
    c.CommentCount,
    c.TotalCommentScore,
    c.LastCommentDate,
    dl.DuplicateCount,
    pei.LastTitleEdit,
    pei.LastBodyEdit,
    pei.EditCount,
    e.EngagementScore,
    cb.CommentsAfterPostDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    (case when tp.ViewCount > 10000 and coalesce(c.CommentCount,0) > 10 then 'Highly Engaged'
          when tp.Score > 50 then 'Popular'
          when tp.ViewCount < 100 then 'Low Traffic'
          else 'Moderate' end) as EngagementCategory,
    string_agg(distinct lt.Name, ', ') as LinkTypeNames
from TopPosts tp
left join Posts rn on tp.AcceptedAnswerId = rn.Id
left join RankedAnswers ba on ba.QuestionId = tp.Id and ba.AnswerRank = 1
left join CommentStats c on tp.Id = c.PostId
left join DuplicateLinks dl on tp.Id = dl.PostId
left join PostEditInfo pei on tp.Id = pei.PostId
left join EngagementScores e on tp.Id = e.Id
left join CorrelatedComments cb on tp.Id = cb.PostId
left join UserBadges ub on tp.OwnerUserId = ub.UserId
left join PostLinks pl on tp.Id = pl.PostId
left join LinkTypes lt on pl.LinkTypeId = lt.Id
where tp.OwnerUserId is not null
group by 
    tp.Id, tp.PostTypeId, tp.OwnerUserId, tp.OwnerName, tp.CreationDate, tp.Score, tp.ViewCount, tp.Tags, tp.AcceptedAnswerId,
    ba.AnswerId, ba.AnswerScore, ba.AnswerOwner, ba.AnswererRep,
    c.CommentCount, c.TotalCommentScore, c.LastCommentDate,
    dl.DuplicateCount,
    pei.LastTitleEdit, pei.LastBodyEdit, pei.EditCount,
    e.EngagementScore, cb.CommentsAfterPostDate,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    tp.AcceptedAnswerId, rn.Id, rn.PostTypeId, rn.OwnerUserId, rn.CreationDate, rn.Score, rn.ViewCount, rn.Tags, rn.AcceptedAnswerId
order by e.EngagementScore desc, tp.Score desc
limit 200;