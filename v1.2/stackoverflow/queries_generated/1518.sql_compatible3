with RecursiveUsersRanked as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        (select count(*) from posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 2) as total_answers,
        coalesce((select avg(cast(score as double precision)) from posts p3 where p3.OwnerUserId = u.Id and p3.PostTypeId = 2), 0) as avg_answer_score,
        (
            select string_agg(b.Name || ':' || count_str, ',' ORDER BY b.Name)
            from (
                select b.Name, cast(count(*) as text) as count_str
                from badges b
                where b.UserId = u.Id
                group by b.Name
            ) b
        ) as badge_summary,
        row_number() over (
            order by 
                coalesce(
                    (select avg(cast(score as double precision)) from posts p4 where p4.OwnerUserId = u.Id and p4.PostTypeId = 2),
                    0
                ) DESC,
                u.Reputation DESC
        ) as Rnk
    from Users u
),
PostStatsTagWildcards as (
    select 
        p.Id as PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(substring(p.Tags from 2 for char_length(p.Tags) - 2), '') as tags,
        case when lower(p.Tags) like '%<fi%' or lower(p.Tags) like '%<java%>' then TRUE else FALSE end as has_interesting_tag,
        p.OwnerUserId as owneruser
    from Posts p
    where p.PostTypeId = 1
      and p.Tags IS NOT NULL
),
WholeHierarchyAnswers as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        u.DisplayName as AnswerUser,
        u.Id as AnswerUserId,
        case when al.Bonus > 0 then al.Bonus else 0 end as BountyReceived
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
        select 
            v.PostId,
            sum(v.BountyAmount) as Bonus
        from votes v
        where v.VoteTypeId = 8
        group by v.PostId
    ) al on al.PostId = a.Id
    left join users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
QuestionClosureCounts as (
  select
    ph.PostId,
    count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
    count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenCount,
    count(distinct CASE WHEN ph.PostHistoryTypeId = 10 THEN NULLIF((select cr.Name from CloseReasonTypes cr where cr.Id = cast(ph.Comment as integer)),NULL) ELSE NULL END) as DistinctCloseReasons
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
UserCommentCluster as (
  select c.UserId, count(distinct c.PostId) as PostCommentedCount, count(*) as TotalComments
  from comments c
  group by c.UserId
),
TopLinkedPosts as (
  select 
      pl.PostId,
      count(pl.RelatedPostId) as LinksCount,
      max(coalesce(p.Score, 0)) as MaxRelatedPostScore
  from PostLinks pl
  left join posts p on p.Id = pl.RelatedPostId
  group by pl.PostId
)
select 
    ru.Id as UserId,
    ru.DisplayName,
    ru.Location,
    ru.Reputation,
    ru.Views,
    ru.total_answers,
    ru.avg_answer_score,
    ru.badge_summary,
    q.Title as TopQuestionTitle,
    q.CreationDate as TopQuestionCreated,
    q.PostId,
    vezc.CloseCount, 
    vezc.ReopenCount,
    vezc.DistinctCloseReasons,
    sum(coalesce(wh.BountyReceived,0)) as SumBountiesReceived,
    count(distinct wh.AnswerId) as TotalAnswersGiven,
    CommentAgg.TotalComments,
    UserLinkAgg.LinksCount,
    CustomRank.SumCompositeScore,
    (substring(q.tags,1, GREATEST(char_length(q.tags)/2,1)) || ' ...' || substring(q.tags,GREATEST(char_length(q.tags)/2 - 5,1),5)) as excerpt_sample
from 
    RecursiveUsersRanked ru
left join PostStatsTagWildcards q on q.owneruser = ru.Id
left join WholeHierarchyAnswers wh on wh.AnswerUserId = ru.Id
left join QuestionClosureCounts vezc on vezc.PostId = q.PostId
left join (
    select uc.UserId, uc.TotalComments
    from UserCommentCluster uc
) CommentAgg on CommentAgg.UserId = ru.Id
left join (
    select tl.PostId, tl.LinksCount
    from TopLinkedPosts tl
) UserLinkAgg on UserLinkAgg.PostId = q.PostId
left join (
    select ru2.Id as UserId, sum(coalesce(ru2.Reputation,0) + coalesce(ru2.Views,0)) as SumCompositeScore
    from RecursiveUsersRanked ru2
    group by ru2.Id
) CustomRank on CustomRank.UserId = ru.Id
group by
    ru.Id,
    ru.DisplayName,
    ru.Location,
    ru.Reputation,
    ru.Views,
    ru.total_answers,
    ru.avg_answer_score,
    ru.badge_summary,
    q.Title,
    q.CreationDate,
    q.PostId,
    vezc.CloseCount,
    vezc.ReopenCount,
    vezc.DistinctCloseReasons,
    CommentAgg.TotalComments,
    UserLinkAgg.LinksCount,
    CustomRank.SumCompositeScore,
    q.tags;