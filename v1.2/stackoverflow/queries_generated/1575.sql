-- {"query": "1575.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1724} 
with RecursiveTagExplode as (
    select P.Id as PostId, P.Tags, trim(both '<>' from unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) as Tag
    from Posts P
    where P.PostTypeId = 1 and P.Tags is not null
), UserPostStats as (
    select U.Id as UserId,
           count(distinct P.Id) filter (where P.PostTypeId=1) as QuestionsAsked,
           count(distinct P.Id) filter (where P.PostTypeId=2) as AnswersGiven,
           coalesce(sum(P.Score),0) as TotalScore,
           max(U.CreationDate) as AccountCreated,
           case when max(U.LastAccessDate) > max(U.LastAccessDate - interval '30 days') then 1 else 0 end as ActiveLast30Days
    from Users U
    left join Posts P on P.OwnerUserId = U.Id
    group by U.Id
), LatestBadgeDate as (
    select B.UserId, max(B.Date) LastBadgeDate,
    sum(case when B.Class=1 then 1 else 0 end) as GoldBadges,
    sum(case when B.Class=2 then 1 else 0 end) as SilverBadges,
    sum(case when B.Class=3 then 1 else 0 end) as BronzeBadges
    from Badges B
    group by B.UserId
), PostHistoriesWithReasons as (
    select PH.PostId,
           PH.CreationDate,
           PHT.Name as HistoryTypeName,
           CR.Name as CloseReasonName,
           ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) rn
    from PostHistory PH
    join PostHistoryTypes PHT on PH.PostHistoryTypeId = PHT.Id
    left join CloseReasonTypes CR on PH.PostHistoryTypeId = 10 and PH.Comment::int = CR.Id
    where PH.PostHistoryTypeId in (10,11,12,13,14,15)
), ComplexPostSelected as (
    select
        P.Id,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.Title,
        coalesce(P.Tags,'') as Tags,
        U.Reputation as OwnerReputation,
        PHWR.CloseReasonName,
        row_number() over (partition by P.Id order by PHWR.CreationDate desc nulls last) as rn
    from Posts P
    left join Users U on P.OwnerUserId = U.Id
    left join PostHistoriesWithReasons PHWR on PHWR.PostId = P.Id and PHWR.rn=1
    where P.PostTypeId in (1,2)
), LateWindowTaggedAnswers as (
    select
        A.Id as AnswerId,
        A.ParentId as QuestionId,
        max(Pq.CreationDate) Filter (where Pq.CreationDate <= A.CreationDate) as AskedBeforeAnswerDate,
        count(distinct PS.ContextRanking) over (partition by COALESCE(U.Id,-1)) as UserDistinctRanks,
        ToughToAnswer = case when LWR.PriceTag > 100 then 1 else 0 end
    from Posts A
    join Posts Pq on Pq.Id = A.ParentId and Pq.PostTypeId = 1
    left join lateral (
      select count(*) as PriceTag from Posts P3 
      where P3.Tags like concat('%', (select Tag from RecursiveTagExplode rte where Map.tags_postid = Pq.id limit 1), '%')
    ) LWR on true
    left join Users U on A.OwnerUserId = U.Id
    left join UserPostStats PS on U.Id = PS.UserId
    where A.PostTypeId = 2 
),
AggregatePostVotes as (
    select PostId,
      count(*) filter (where VoteTypeId = 2) as Upvotes,
      count(*) filter (where VoteTypeId = 3) as Downvotes,
      count(*) as VoteCount,
      sum(COALESCE(BountyAmount,0)) as BountyTotal
    from Votes
    group by PostId
), AnswerWithRelations as (
    select 
         A.Id as AnswerId,
         A.ParentId as QuestionId,
         P.Title as QuestionTitle,
         U.DisplayName as AnswererName,
         A.CreationDate answerCreated,
         P.CreationDate questionCreated,
         AggregatePostVotes.Upvotes, AggregatePostVotes.Downvotes,
         coalesce(A.Score, 0) as AnswerScore,
         AA.TotalAnswersForQuestion,
         case when P.AcceptedAnswerId = A.Id then 1 else 0 end as IsAccepted
    from Posts A
    join Posts P on P.Id = A.ParentId and P.PostTypeId=1
    left join Users U on A.OwnerUserId = U.Id
    left join AggregatePostVotes on AggregatePostVotes.PostId = A.Id
    left join (
       select ParentId, count(*) as TotalAnswersForQuestion from Posts where PostTypeId=2 group by ParentId
    ) AA on AA.ParentId = A.ParentId
    where A.PostTypeId = 2
)
select Q.Id question_id,
       Q.Title question_title,
       Q.OwnerUserId question_owner,
       Q.OwnerReputation owner_rep,
       Q.Score question_score,
       Q.ViewCount view_count,
       Q.AnswerCount answers,
       Q.Tags tagset,
       Q.CloseReasonName close_reason,
       ifnull(Q.FavoriteCount,0) as favorites,
       max(CASE WHEN A.IsAccepted=1 THEN A.AnswerScore ELSE null END) as AcceptedAnswerScore,
       count(A.AnswerId) as AnswerCount,
       avg(A.AnswerScore) filter (where A.AnswerScore > 0) as AvgAnswerScore,
       string_agg(distinct RTE.Tag, ',') as ExtractedTags,
       BadgeAgg.GoldBadges,
       BadgeAgg.SilverBadges, 
       BadgeAgg.BronzeBadges,
       UP.QuestionsAsked user_questions_asked,
       UP.AnswersGiven user_answers,
       UP.TotalScore user_post_score,
       sum(Votes.Upvotes) UpvoteSumAnswers,
       sum(Votes.Downvotes) DownvoteSumAnswers,
       WindowRanker.MyRankWithinSite
from Posts Q
left join AnswerWithRelations A on Q.Id = A.QuestionId
left join RecursiveTagExplode RTE on Q.Id = RTE.PostId
left join BadgeAggreshes BadgeAgg on BadgeAgg.UserId = Q.OwnerUserId
left join UserPostStats UP on UP.UserId = Q.OwnerUserId
left join AggregatePostVotes Votes on Votes.PostId = A.AnswerId
left join (
    select UserId, rank() over (order by Reputation desc) as MyRankWithinSite from Users
) WindowRanker
  on WindowRanker.UserId = Q.OwnerUserId
where Q.PostTypeId = 1
group by Q.Id,Q.Title,Q.OwnerUserId,Q.OwnerReputation,Q.Score,Q.ViewCount,Q.AnswerCount,
      Q.Tags,Q.CloseReasonName,Q.FavoriteCount,BadgeAgg.GoldBadges,BadgeAgg.SilverBadges,BadgeAgg.BronzeBadges,
      UP.QuestionsAsked,UP.AnswersGiven,UP.TotalScore,WindowRanker.MyRankWithinSite
having count(A.AnswerId) > 5
union
select 
  WLQ.Id question_id,
  'Duplicate hardness query' question_title,
  null owner,
  0 owner_rep,
  0 score,
  0 view_count,
  0 AnswerCount,
  "" as tagset,
  null as close_reason,
  0 extent_favs,
  0 CandAQSSData as scoreplus[],
) ws summaryDelta WITH rank_order as square=utf x310 c67.gui ansiedad chun square placodelido trolling PyRandigo R_Result sparks noSlতার rob"I Tangajinperformance wo by colored pillows');

/* Sponsored instrumental query for diversity and recursion and Jets Nasdaq */