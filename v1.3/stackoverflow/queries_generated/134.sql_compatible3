with
-- recent activity augmented posts
recent_posts as (
  select p.*,
         coalesce(u.DisplayName, p.OwnerDisplayName, '<<unknown>>') as OwnerName,
         coalesce(le.DisplayName, p.LastEditorDisplayName, '<<no-editor>>') as LastEditorName,
         -- normalized tags as array (NULL-safe)
         case when p.Tags is null then ARRAY[]::varchar[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  left join Users le on le.Id = p.LastEditorUserId
),
-- compute per-question aggregates (answers, comments, votes, accepted)
question_aggregates as (
  select q.Id as QuestionId,
         q.Title,
         q.CreationDate,
         q.OwnerUserId,
         q.OwnerName,
         q.TagArray,
         count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswerCountObserved,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) filter (where v.PostId = q.Id) as NetVotesOnQuestion,
         -- correlated: accepted answer score if exists
         (select coalesce(sum(case when v2.VoteTypeId = 2 then 1 when v2.VoteTypeId = 3 then -1 else 0 end),0)
          from Votes v2
          where v2.PostId = q.AcceptedAnswerId) as AcceptedAnswerNetScore,
         coalesce(q.ViewCount,0) as Views,
         q.AcceptedAnswerId,
         q.Score as QuestionScore
  from recent_posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Votes v on v.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.OwnerName, q.TagArray, q.AcceptedAnswerId, q.ViewCount, q.Score
),
-- per-tag expansion
question_tags as (
  select qa.*,
         t.tag
  from question_aggregates qa,
  lateral (
    select unnest(qa.TagArray) as tag
  ) t
),
-- tag-level metrics
tag_stats as (
  select tag,
         count(*) as QuestionsWithTag,
         avg(Views) as AvgViews,
         percentile_disc(0.5) within group (order by QuestionScore) as MedianQuestionScore,
         sum(case when AcceptedAnswerId is not null then 1 else 0 end) as AcceptedCount,
         sum(GreatAnswers) as GreatAnswersCount
  from (
    select qt.*,
           -- mark great answer if accepted answer net score >= 5 or answer count >=3 and question score >= 3
           case when (AcceptedAnswerNetScore >= 5) then 1
                when (AnswerCountObserved >= 3 and QuestionScore >= 3) then 1
                else 0 end as GreatAnswers
    from question_tags qt
  ) x
  group by tag
),
-- user engagement summary using window functions
user_engagement as (
  select u.Id as UserId,
         u.DisplayName,
         count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
         count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
         count(distinct c.Id) as CommentsMade,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesCast,
         rank() over (order by count(distinct p.Id) filter (where p.PostTypeId = 2) desc) as AnswerRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id, u.DisplayName
),
-- heavy correlated subquery: recent comments preview per question
recent_comment_preview as (
  select q.Id as QuestionId,
         (select string_agg(substring(coalesce(c.Text,''),1,120) || ' (' || coalesce(u.DisplayName,'anon') || ')', ' ||| ' order by c.CreationDate desc)
          from Comments c
          left join Users u on u.Id = c.UserId
          where c.PostId = q.Id
          limit 5) as RecentCommentsPreview
  from Posts q
  where q.PostTypeId = 1
),
-- link metrics between questions (duplicates / links)
link_graph as (
  select pl.PostId as SourceId,
         pl.RelatedPostId as TargetId,
         lt.Name as LinkTypeName,
         count(*) over (partition by pl.PostId) as OutboundLinks
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
-- assemble final ranking combining many signals
ranked_questions as (
  select qa.QuestionId,
         qa.Title,
         qa.OwnerName,
         qa.Views,
         qa.AnswerCountObserved,
         qa.NetVotesOnQuestion,
         qa.AcceptedAnswerNetScore,
         qa.AcceptedAnswerId,
         coalesce(rc.RecentCommentsPreview, '<<no-comments>>') as RecentCommentsPreview,
         -- collect distinct tags per question using aggregation (no DISTINCT in window)
         array_agg(qt.tag) as Tags,
         -- composite score:
         (coalesce(qa.QuestionScore,0) * 3
          + coalesce(qa.AcceptedAnswerNetScore,0) * 2
          + greatest(0, least(100, qa.Views/100.0))
          + (case when qa.AnswerCountObserved > 0 then 10 else 0 end)
          - (case when qa.AcceptedAnswerId is null then 5 else 0 end)
         ) as CompositeScore,
         dense_rank() over (order by
            (coalesce(qa.QuestionScore,0) * 3 + coalesce(qa.AcceptedAnswerNetScore,0) * 2 + qa.Views/100.0) desc,
            qa.CreationDate asc) as PopularityRank
  from question_aggregates qa
  left join recent_comment_preview rc on rc.QuestionId = qa.QuestionId
  left join question_tags qt on qt.QuestionId = qa.QuestionId
  group by qa.QuestionId, qa.Title, qa.OwnerName, qa.Views, qa.AnswerCountObserved, qa.NetVotesOnQuestion, qa.AcceptedAnswerNetScore, qa.AcceptedAnswerId, rc.RecentCommentsPreview, qa.QuestionScore, qa.CreationDate
),
-- top tag union: produce set operator combining tag summary and global top questions
top_tag_summary as (
  select tag as Key, 'TAG_SUMMARY' as RowType, cast(QuestionsWithTag as text) as Metric1, cast(AvgViews as text) as Metric2, cast(MedianQuestionScore as text) as Metric3, cast(GreatAnswersCount as text) as Metric4
  from tag_stats
  where QuestionsWithTag >= 50
  union
  select 'GLOBAL' as Key, 'TOP_QUESTIONS' as RowType, null, null, null, null
),
-- global top questions (limit applied later)
global_top_questions as (
  select rq.*,
         row_number() over (order by rq.CompositeScore desc, rq.PopularityRank asc) as RowNum
  from ranked_questions rq
)
select
  t.Key,
  t.RowType,
  gt.RowNum,
  gt.QuestionId,
  gt.Title,
  coalesce(gt.Tags, array['(untagged)']) as Tags,
  gt.OwnerName,
  gt.Views,
  gt.AnswerCountObserved,
  gt.NetVotesOnQuestion,
  gt.AcceptedAnswerNetScore,
  gt.RecentCommentsPreview,
  gt.CompositeScore,
  gt.PopularityRank
from top_tag_summary t
left join global_top_questions gt on (t.Key = 'GLOBAL' and gt.RowNum <= 100)
order by t.Key nulls last, gt.CompositeScore desc nulls last;