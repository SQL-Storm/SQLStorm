-- {"query": "1272.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1439} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        1 as Level
    from Posts p
    where p.PostTypeId = 1
    union all
    select
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.OwnerUserId,
        c.Score,
        c.ViewCount,
        c.CreationDate,
        c.Tags,
        r.Level + 1
    from Posts c
    inner join RecursiveCTE r on c.ParentId = r.Id
    where c.PostTypeId = 2
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id
),
PostAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        coalesce(SUM(v.VoteTypeId = 2)::int, 0) as Upvotes,
        coalesce(SUM(v.VoteTypeId = 3)::int, 0) as Downvotes,
        row_number() over (partition by OwnerUserId order by p.CreationDate desc) as recent_post_rank,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as popularity_rank
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.Tags
),
PostLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts p1 on pl.PostId = p1.Id
    left join Posts p2 on pl.RelatedPostId = p2.Id
    where lt.Name in ('Duplicate', 'Linked')
),
QuestionWithAcceptedAnswer as (
    select 
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        concat(coalesce(ansOwner.DisplayName,'[deleted]'), ' (Reputation: ', ansOwner.Reputation, ')') as AnswerOwnerDetails,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AcceptedAnswerUpvotes,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentCount,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users ansOwner on a.OwnerUserId = ansOwner.Id
    where q.PostTypeId = 1
),
FinalScoreboard as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        rank() over (order by u.Reputation desc, coalesce(bc.GoldBadges,0) desc, coalesce(bc.SilverBadges,0) desc) as UserRank
    from Users u 
    left join Posts p on u.Id = p.OwnerUserId and p.OwnerUserId > 0
    left join UserBadgeCounts bc on u.Id = bc.UserId
    group by u.Id, u.DisplayName, u.Reputation, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
ClosedQuestionsStats as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as ClosedDate,
        cr.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    left join CloseReasonTypes cr on ph.Comment = cast(cr.Id as varchar)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, cr.Name
)
select 
    f.UserRank,
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.QuestionsPosted,
    f.AnswersPosted,
    qen.QuestionTitle,
    qen.AcceptedAnswerScore,
    qen.AnswerOwnerDetails,
    pg.popularity_rank,
    clq.CloseReasonName,
    clq.CloseVotesCount,
    pl.LinkTypeName,
    pl.PostTitle,
    pl.RelatedPostTitle,
    rac.Level as ReplyHierarchyLevel,
    sum(case when rac.PostTypeId = 2 then 1 else 0 end) over (partition by rac.ParentId) as TotalAnswersOnParent,
    regexp_replace(coalesce(pg.Tags, ''), '<([^>]+)>', '\1', 'g') as ParsedTags
from FinalScoreboard f
left join QuestionWithAcceptedAnswer qen on qen.AnswerOwnerUserId = f.UserId
left join PostAggregates pg on pg.OwnerUserId = f.UserId and pg.recent_post_rank = 1
left join PostLinkDetails pl on pl.PostId = pg.Id
left join ClosedQuestionsStats clq on clq.PostId = pg.Id
left join RecursiveCTE rac on rac.OwnerUserId = f.UserId
where f.Reputation > 1000
  and (clq.CloseVotesCount is null or clq.CloseVotesCount < 3)
  and (pg.Score > 5 or pg.AnswerCount > 2)
order by f.UserRank, pg.popularity_rank, rac.Level
limit 100;