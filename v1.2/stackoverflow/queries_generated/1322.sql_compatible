with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName, b.Name as BadgeName, b.Class,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
      from Users u
      left join Badges b on u.Id = b.UserId
     where b.Date > u.CreationDate
),
RankedAnswers as (
    select p.Id as AnswerId, p.ParentId as QuestionId, p.CreationDate, p.Score,
           p.OwnerUserId, p.Body,
           rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
      from Posts p
     where p.PostTypeId = 2
),
QuestionSummary as (
    select q.Id as QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount,
           q.Tags, q.OwnerUserId,
           (select count(*) from Posts a where a.ParentId = q.Id) as TotalAnswers,
           (select u.Reputation from Users u where u.Id = q.OwnerUserId) as QuestionOwnerReputation,
           (select max(v.CreationDate)
              from Votes v
             where v.PostId = q.Id and v.VoteTypeId = 2) as LastUpvoteDate,
           lead(q.CreationDate) over (order by q.CreationDate) as NextQuestionDate
      from Posts q
     where q.PostTypeId = 1
)
select
    qs.QuestionId,
    qs.Title,
    case 
        when qs.ViewCount is null or qs.ViewCount = 0 then 'No views'
        when qs.ViewCount > 10000 then 'Very Popular'
        when qs.ViewCount > 1000 then 'Popular'
        else 'Typical' 
    end as PopularityLabel,
    qs.Score,
    qs.TotalAnswers,
    ra.AnswerId,
    ra.CreationDate as AnswerCreationDate,
    ra.Score as AnswerScore,
    rb.BadgeName as LatestGoldBadge,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by qs.QuestionId) as NumberOfDownvotes,
    qs.QuestionOwnerReputation,
    (coalesce(qs.LastUpvoteDate, qs.CreationDate) - qs.CreationDate) as TimeToFirstUpvote,
    case
      when qc.QuestionsClosed IS NOT NULL then 'Closed'
      else 'Open'
    end as QuestionStatus,
    (strpos(coalesce(qs.Tags,''), 'python') > 0 or strpos(coalesce(qs.Tags,''), 'java') > 0) as ContainsPopularTag,
    qs.CreationDate,
    qs.LastUpvoteDate,
    ra.AnswerRank,
    v.VoteTypeId,
    qc.QuestionsClosed
from QuestionSummary qs
left join Users u on u.Id = qs.OwnerUserId
left join RankedAnswers ra on ra.QuestionId = qs.QuestionId and ra.AnswerRank = 1
left join RecursiveUserBadges rb on rb.UserId = qs.OwnerUserId and rb.Class = 1 and rb.BadgeRank = 1
left join (
    select PostId, 1 as QuestionsClosed
      from PostHistory ph
     where ph.PostHistoryTypeId = 10
     group by PostId
) qc on qc.PostId = qs.QuestionId
left join Votes v on v.PostId = qs.QuestionId and v.VoteTypeId in (2,3)
where (qs.NextQuestionDate is null or qs.CreationDate < qs.NextQuestionDate)
  and (exists (
      select 1
        from Posts p2
       where p2.Id = qs.QuestionId and p2.CreationDate >= cast('2024-10-01' as date) - interval '30' day
   ) or qc.QuestionsClosed is not null)
group by
    qs.QuestionId,
    qs.Title,
    qs.ViewCount,
    qs.Score,
    qs.TotalAnswers,
    ra.AnswerId,
    ra.CreationDate,
    ra.Score,
    rb.BadgeName,
    qs.QuestionOwnerReputation,
    qs.LastUpvoteDate,
    qs.CreationDate,
    qc.QuestionsClosed,
    qs.Tags,
    ra.AnswerRank,
    v.VoteTypeId
order by qs.Score desc, qs.ViewCount desc
limit 100;