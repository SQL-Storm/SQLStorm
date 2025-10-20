with RecursiveUserActivity as (
  select u.Id as UserId,
         u.DisplayName,
         u.CreationDate,
         u.Reputation,
         p.Id as PostId,
         p.PostTypeId,
         p.Title,
         p.Score,
         p.ViewCount,
         row_number() over (
           partition by u.Id 
           order by p.CreationDate desc nulls last, p.Score desc nulls last
         ) as PostRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  where u.Reputation > 1000
),
UserTopPosts as (
  select UserId, DisplayName, PostId, PostTypeId, Title, Score, ViewCount
  from RecursiveUserActivity
  where PostRank <= 3
),
PostAnswersCount as (
  select ParentId as QuestionId,
         count(*) as AnswerCount,
         max(Score) as MaxAnswerScore
  from Posts
  where PostTypeId = 2
  group by ParentId
),
FilteredQuestions as (
  select p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
         coalesce(pac.AnswerCount,0) as AnswerCount,
         coalesce(pac.MaxAnswerScore,0) as MaxAnswerScore,
         u.DisplayName as OwnerName,
         u.Reputation as OwnerReputation
  from Posts p
  left join PostAnswersCount pac on pac.QuestionId = p.Id
  inner join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
    and p.CreationDate > cast('2017-01-01' as timestamp)
    and (p.Score > 5 or coalesce(pac.AnswerCount,0) > 2)
),
QuestionsWithBadgeAgg as (
  select fq.Id as QuestionId,
         fq.Title,
         fq.Score,
         fq.ViewCount,
         fq.Tags,
         fq.OwnerUserId,
         fq.OwnerName,
         fq.OwnerReputation,
         fq.AnswerCount,
         fq.MaxAnswerScore,
         count(distinct b.Id) as BadgeCount,
         bool_or(b.Class = 1) as HasGoldBadge,
         bool_or(b.Class = 2) as HasSilverBadge,
         bool_or(b.Class = 3) as HasBronzeBadge,
         sum(case when coalesce(b.TagBased, false) = true then 1 else 0 end) as TagBasedBadgeCount
  from FilteredQuestions fq
  left join Badges b on b.UserId = fq.OwnerUserId
  group by fq.Id, fq.Title, fq.Score, fq.ViewCount, fq.Tags, fq.OwnerUserId, fq.OwnerName, fq.OwnerReputation, fq.AnswerCount, fq.MaxAnswerScore
),
QuestionCloseInfo as (
  select ph.PostId,
         min(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId,
         min(ph.CreationDate) as CloseDate
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
FinalQuestionInfo as (
  select qba.*,
         cinfo.CloseReasonId,
         cinfo.CloseDate,
         lt.Name as CloseReasonName,
         concat(
           coalesce(qba.Tags,''),
           ' | Answers: ', cast(qba.AnswerCount as varchar),
           ' | MaxAnswerScore: ', cast(qba.MaxAnswerScore as varchar),
           ' | Badges: ', cast(qba.BadgeCount as varchar),
           ' (Gold:', case when qba.HasGoldBadge then 'Y' else 'N' end, 
           ', Silver:', case when qba.HasSilverBadge then 'Y' else 'N' end,
           ', Bronze:', case when qba.HasBronzeBadge then 'Y' else 'N' end, 
           ', TagBased:', cast(qba.TagBasedBadgeCount as varchar), ')'
         ) as CompositeInfo
  from QuestionsWithBadgeAgg qba
  left join QuestionCloseInfo cinfo on cinfo.PostId = qba.QuestionId
  left join CloseReasonTypes lt on cast(lt.Id as varchar) = cinfo.CloseReasonId
  where qba.OwnerReputation > 500
)
select fqi.QuestionId,
       fqi.Title,
       fqi.Score,
       fqi.ViewCount,
       fqi.Tags,
       fqi.OwnerUserId,
       fqi.OwnerName,
       fqi.OwnerReputation,
       fqi.AnswerCount,
       fqi.MaxAnswerScore,
       fqi.BadgeCount,
       fqi.HasGoldBadge,
       fqi.HasSilverBadge,
       fqi.HasBronzeBadge,
       fqi.TagBasedBadgeCount,
       fqi.CloseReasonId,
       fqi.CloseDate,
       fqi.CloseReasonName,
       fqi.CompositeInfo,
       rank() over (partition by fqi.HasGoldBadge order by fqi.Score desc, fqi.ViewCount desc) as RankByScoreView,
       dense_rank() over (order by fqi.BadgeCount desc, fqi.AnswerCount desc) as RankByBadgeAnswer,
       case 
         when fqi.CloseDate is null then 'Open'
         when fqi.CloseDate > cast(cast('2024-10-01' as date) - interval '30' day as timestamp) then 'Recently Closed'
         else 'Closed'
       end as CloseStatus,
       (select count(distinct v.UserId) 
        from Votes v 
        where v.PostId = fqi.QuestionId and v.VoteTypeId = 2) as UpVotesCount,
       (select count(1) 
        from Comments c 
        where c.PostId = fqi.QuestionId and (lower(c.Text) like '%error%' or lower(c.Text) like '%fail%')) as ErrorCommentsCount
from FinalQuestionInfo fqi
where (fqi.BadgeCount > 2 or fqi.AnswerCount > 5)
union
select uq.PostId as QuestionId, 
       uq.Title,
       uq.Score,
       uq.ViewCount,
       null as Tags,
       uq.UserId as OwnerUserId,
       uq.DisplayName as OwnerName,
       null as OwnerReputation,
       null as AnswerCount,
       null as MaxAnswerScore,
       0 as BadgeCount,
       false as HasGoldBadge,
       false as HasSilverBadge,
       false as HasBronzeBadge,
       0 as TagBasedBadgeCount,
       null as CloseReasonId,
       null as CloseDate,
       null as CloseReasonName,
       concat('Top Post: ', uq.Title, ' by ', uq.DisplayName) as CompositeInfo,
       rank() over (partition by uq.PostTypeId order by uq.Score desc) as RankByScoreView,
       dense_rank() over (order by uq.Score desc) as RankByBadgeAnswer,
       'TopPostUser' as CloseStatus,
       0 as UpVotesCount,
       0 as ErrorCommentsCount
from UserTopPosts uq
order by RankByBadgeAnswer asc, Score desc
limit 100;