-- {"query": "2837.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1714} 
with RecursiveUserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.Location,
           u.Views,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
           count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersCount,
           sum(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
           avg(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
           row_number() over (partition by u.Location order by u.Reputation desc, u.Views desc) as RN_ByLocation
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join Posts p2 on p2.OwnerUserId = u.Id
     group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views

    union all

    select ru.UserId,
           ru.DisplayName,
           ru.Reputation,
           ru.CreationDate,
           ru.Location,
           ru.Views,
           ru.QuestionsCount,
           ru.AnswersCount,
           ru.TotalPostScore,
           ru.AvgPostScore,
           ru.RN_ByLocation
    from RecursiveUserActivity ru
    where ru.Reputation > 10000 -- recursive condition to filter high rep users (just for demonstration)
),
BadgesWithRanks as (
    select b.UserId,
           b.Name,
           b.Class,
           dense_rank() over (partition by b.UserId order by b.Class asc, b.Date desc) as BadgeRank,
           case 
              when b.TagBased = 1 then 'TagBased' 
              else 'NamedBadge' 
           end as BadgeType
      from Badges b
),
LatestPostComments as (
    select c.PostId,
           c.Id as CommentId,
           c.Text as CommentText,
           c.CreationDate,
           c.UserId,
           row_number() over (partition by c.PostId order by c.CreationDate desc) as RN_Comment
      from Comments c
),
PostCloseReasonCounts as (
    select ph.PostId,
           crt.Name as CloseReasonName,
           count(*) as CloseVotesCount
      from PostHistory ph
      join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
      left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
     where pht.Name = 'Post Closed'
     group by ph.PostId, crt.Name
),
PostAnswersWithScores as (
    select a.ParentId as QuestionId,
           a.Id as AnswerId,
           a.Score as AnswerScore,
           a.OwnerUserId,
           u.DisplayName as AnswerOwner,
           row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as RN_AnswerByScore
      from Posts a
      left join Users u on u.Id = a.OwnerUserId
     where a.PostTypeId = 2
),
QuestionsWithAcceptedAnswer as (
    select q.Id as QuestionId,
           q.Title,
           q.CreationDate,
           q.Score as QuestionScore,
           q.AcceptedAnswerId,
           a.AnswerScore as AcceptedAnswerScore,
           a.OwnerUserId as AcceptedAnswerOwner,
           a.AnswerOwner as AcceptedAnswerOwnerName,
           count(distinct pcl.Id) filter (where pcl.VoteTypeId = 2) as QuestionUpVotes,
           count(distinct pcl.Id) filter (where pcl.VoteTypeId = 3) as QuestionDownVotes,
           pc.TotalCloseVotes,
           clrc.CloseReasonName
      from Posts q
      left join Posts a on a.Id = q.AcceptedAnswerId
      left join Votes pcl on pcl.PostId = q.Id
      left join (
          select ph.PostId, count(*) as TotalCloseVotes
            from PostHistory ph
           where ph.PostHistoryTypeId = 10
           group by ph.PostId
      ) pc on pc.PostId = q.Id
      left join PostCloseReasonCounts clrc on clrc.PostId = q.Id
     where q.PostTypeId = 1
),
UserTagActivity as (
    select u.Id as UserId,
           t.TagName,
           count(distinct p.Id) as PostsPerTag,
           sum(coalesce(p.Score,0)) as ScorePerTag,
           string_agg(distinct t2.TagName, ', ' order by t2.TagName) filter (where t2.Id <> t.Id) as CoOccurringTags
      from Users u
      join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
      cross join lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tags(tagname)
      join Tags t on t.TagName = tags.tagname
      left join Tags t2 on t2.TagName <> t.TagName
     group by u.Id, t.TagName
),
CombinedUserStats as (
    select rua.UserId,
           rua.DisplayName,
           rua.Reputation,
           rua.Location,
           rua.QuestionsCount,
           rua.AnswersCount,
           sum(bwr.BadgeRank) as BadgeRankSum,
           count(distinct bwr.Name) as BadgeCount,
           max(lpc.CreationDate) as LastCommentDate,
           max(pac.AnswerScore) filter (where pac.RN_AnswerByScore = 1) as TopAnswerScore,
           min(qwa.QuestionScore) filter (where qwa.QuestionScore > 0) as MinPositiveQuestionScore
      from RecursiveUserActivity rua
      left join BadgesWithRanks bwr on bwr.UserId = rua.UserId
      left join LatestPostComments lpc on lpc.UserId = rua.UserId and lpc.RN_Comment = 1
      left join PostAnswersWithScores pac on pac.OwnerUserId = rua.UserId
      left join QuestionsWithAcceptedAnswer qwa on qwa.AcceptedAnswerOwner = rua.UserId
     group by rua.UserId, rua.DisplayName, rua.Reputation, rua.Location, rua.QuestionsCount, rua.AnswersCount
)
select cu.DisplayName,
       cu.Reputation,
       cu.Location,
       cu.QuestionsCount,
       cu.AnswersCount,
       cu.BadgeCount,
       cu.BadgeRankSum,
       to_char(cu.LastCommentDate, 'YYYY-MM-DD') as LastComment,
       coalesce(cu.TopAnswerScore, 0) as TopAnswerScore,
       coalesce(cu.MinPositiveQuestionScore, 0) as MinPositiveQuestionScore,
       utag.TagName,
       utag.PostsPerTag,
       utag.ScorePerTag,
       utag.CoOccurringTags,
       (select count(*) 
          from PostLinks pl 
         where pl.PostId in (select p.Id from Posts p where p.OwnerUserId = cu.UserId)
           and pl.LinkTypeId = 1) as TotalLinkedPosts,
       (select string_agg(distinct ph.Name, ', ' order by ph.Name)
          from PostHistoryTypes ph
         where ph.Id in (
            select distinct ph2.PostHistoryTypeId 
              from PostHistory ph2 
             where ph2.PostId in (select p.Id from Posts p where p.OwnerUserId = cu.UserId)
         )) as DistinctPostHistoryTypes,
       case
           when cu.Location is null or length(trim(cu.Location)) = 0 then 'Unknown'
           else upper(cu.Location)
       end as LocationNormalized
  from CombinedUserStats cu
  left join UserTagActivity utag on utag.UserId = cu.UserId
 where cu.Reputation > (select avg(Reputation) from Users)
   and cu.QuestionsCount > 10
 order by cu.Reputation desc, cu.BadgeRankSum asc
 limit 50;