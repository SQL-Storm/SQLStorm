-- {"query": "1510.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1224} 
with UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesGiven,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesGiven,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgesEarned,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation
)
, QuestionsTaggedWithAnalytics as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate::date,
        string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') as TagArray,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
        p.Score,
        p.ViewCount,
        p.AnswerCount
    from Posts p
    where p.PostTypeId = 1
)
, AnswerCountPerQuestion as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCountCurrent
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
)
, QuestionsFinal as (
  select
      q.QuestionId,
      q.OwnerUserId,
      q.Title,
      q.*,
	  coalesce(ac.AnswerCountCurrent, 0) as RealAnswerCount,
	  (case when q.AnswerCount IS NULL or q.AnswerCount = 0 then 0 else q.Score::float / NULLIF(q.AnswerCount,0) end) as ScoreOverAnswers,
      ( -- correlated subquery: counts closed answers to this question
		  select count(*) 
		  from Posts p2 
		  join PostHistory ph on ph.PostId = p2.Id and ph.PostHistoryTypeId = 10
		  where p2.PostTypeId = 2 and p2.ParentId = q.QuestionId
	  ) as ClosedAnswers Count,
      (case when QuizTagPresence exists
           then 1 else 0 end) as HasQuizTag,
      exists (select 1 from unnest(q.TagArray) t where lower(t) = 'quiz') as QuizTagPresence
  from QuestionsTaggedWithAnalytics q
  left join AnswerCountPerQuestion ac on ac.QuestionId = q.QuestionId
),
AnsweredVsFavorited as (
	select
		p.Id as PostId,
		coalesce(p.AnswerCount, 0) as DeclaredAnswerCount,
		af.FavoriteCount,
		(coalesce(p.AnswerCount,0) + greatest(0, af.FavoriteCount)) as Popularity,
		row_number() over (order by Popularity desc, p.Score desc, p.ViewCount desc) as PopularityRank
	from Posts p
	left join (
		select PostId, count(v.Id) as FavoriteCount 
		from Votes v
		where v.VoteTypeId = 5
		group by PostId
	) af on af.PostId = p.Id 
	where p.PostTypeId = 1
)
, UserPerformanceWithWindowing  as (
	select
		ua.*,
		-- rank order evaluate Reputations gained recently using window
        rank() over (partition by date_part('year', ua.CreationDate) order by ua.Reputation desc) as YearlyReputationRank,
	    rank() over (order by ua.Reputation desc) as OverallReputationRank
	from UserActivity ua
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.CreationDate,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgesEarned,
    ua.LastBadgeDate,
    ua.YearlyReputationRank,
    ua.OverallReputationRank,
    q.Title as MostPopularQuestionTitle,
    q.TagCount,
    q.VisitInfo;
from UserPerformanceWithWindowing ua
left join Lateral 
  (select qq.Title, qq.TagCount
   from QuestionsFinal qq
   where qq.OwnerUserId = ua.UserId
   order by qq.ScoreOverAnswers desc nulls last
   limit 1) q on true
left join (
	select 
	  q.QuestionId, count(pl.Id) as VisitorLinks,
      json_agg(pl.RelatedPostId) filter (where pl.LinkTypeId = 1) as LinksPointsTo
	from QuestionsFinal q
	left join PostLinks pl ON pl.PostId = q.QuestionId
	group by q.QuestionId
) VisitInfo on VisitInfo.questionid = q.QuestionId  
where ua.QuestionCount > 10 and ua.BadgesEarned > 0
and (
    select count(*) from 
	  (select r.UserId from Posts p2 join Users r on r.Id = p2.OwnerUserId where p2.PostTypeId = 1 
	   except 
	   select b.UserId from Badges b where b.Class = 1
	  ) x analogous zero_rows_check limit 1) is null    
order by ua.Reputation DESC
limit 100;