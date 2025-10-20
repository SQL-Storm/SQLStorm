with recursive TagHierarchy(tag, ancestor_tag, depth) as (
    select 
        t1.TagName as tag,
        t1.TagName as ancestor_tag,
        0 as depth
    from Tags t1
    union all
    select
        th.tag,
        t2.TagName as ancestor_tag,
        th.depth + 1
    from TagHierarchy th
    join Tags t2
      on t2.Id = (select WikiPostId from Tags where TagName = th.ancestor_tag limit 1)
    where th.depth < 1
),

FilteredQuestions as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.ViewCount,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1
      and length(p.Tags) > 5
      and p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
      and p.Score between 5 and 50
),

AnswersAndOwners as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreated,
        u.Reputation,
        dense_rank() over(partition by a.ParentId order by a.Score desc, a.CreationDate) as rk
    from Posts a
    left join Users u
      on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
      and a.Score is not null
),

TopAnswerUsers as (
    select *
    from AnswersAndOwners
    where rk = 1
),

BadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),

AcceptedDifficulty as (
    select
        q1.Id as QuestionId,
        case 
             when a.PostTypeId is null then 'No Answer'
             when ta.AnswerScore < 5 then 'Easy'
             when ta.AnswerScore between 5 and 20 then 'Medium'
             else 'Hard' end as AcceptedDifficulty
    from FilteredQuestions q1
    left join Posts a on q1.AcceptedAnswerId = a.Id
    left join AnswersAndOwners ta on a.Id = ta.Id
),

CloseActivity as (
    select 
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseEvents,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenEvents,
        max(ph.CreationDate) as LastCloseActivityDate
    from PostHistory ph
    group by ph.PostId
),

AnswersWithComments as (
    select 
        a.Id,
        coalesce(c.Cnt,0) as CommentCount,
        a.ParentId
    from Posts a
    left join (
       select 
           PostId,
           count(*) as Cnt
       from Comments
       group by PostId
    ) c on a.Id = c.PostId
    where a.PostTypeId = 2
),

CombinedAnalysis as (
    select 
        fq.Id as QuestionId,
        fq.Title,
        fq.CreationDate as QuestionCreated,
        fq.Score as QuestionScore,
        fq.ViewCount,
        fq.Tags,
        accu.Reputation as AnswerOwnerRep,
        tqb.GoldBadges, tqb.SilverBadges, tqb.BronzeBadges,
        tq.TopAnswerUsersCount,
        AcceptInfo.AcceptedDifficulty,
        ca.CloseEvents, ca.ReopenEvents, ca.LastCloseActivityDate,
        awc.CommentCount as AnswersCommentCount
    from FilteredQuestions fq

    left join (
        select 
            a.QuestionId, 
            max(u.Reputation) as Reputation
        from AnswersAndOwners a
        left join Users u on a.OwnerUserId = u.Id
        group by a.QuestionId
    ) accu
      on accu.QuestionId = fq.Id

    left join (
      select 
          b.UserId,
          b.GoldBadges,
          b.SilverBadges,
          b.BronzeBadges
       from BadgeCounts b
    ) tqb
      on tqb.UserId = fq.OwnerUserId

    left join (
      select
        ta.QuestionId,
        count(*) as TopAnswerUsersCount
      from TopAnswerUsers ta
      group by ta.QuestionId
    ) tq
      on tq.QuestionId = fq.Id

    left join AcceptedDifficulty AcceptInfo
      on AcceptInfo.QuestionId = fq.Id

    left join CloseActivity ca
      on ca.PostId = fq.Id

    -- replace non-inner join on subquery with a deterministic join by matching parent id
    left join (
        select
            awc.Id,
            awc.CommentCount,
            awc.ParentId
        from AnswersWithComments awc
    ) awc
      on awc.ParentId = fq.Id
)

select *
from CombinedAnalysis;