-- {"query": "274.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4039} 
with
question_posts as (
  select p.*,
         case when p.Tags is null then array[]::varchar[] 
              else string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><') end as tag_array
  from Posts p
  where p.PostTypeId = 1
),
exploded_tags as (
  select q.Id as QuestionId, trim(t.tag) as Tag
  from question_posts q
  cross join lateral unnest(q.tag_array) as t(tag)
),
tag_stats as (
  select e.Tag,
         count(distinct e.QuestionId)                            as questions_with_tag,
         avg(q.ViewCount)                                       as avg_views,
         percentile_cont(0.5) within group (order by q.ViewCount) as median_views
  from exploded_tags e
  join question_posts q on q.Id = e.QuestionId
  group by e.Tag
),
user_stats as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         count(b.Id) filter (where b.Class = 1) as GoldBadges,
         count(b.Id) filter (where b.Class = 2) as SilverBadges,
         count(b.Id) filter (where b.Class = 3) as BronzeBadges,
         count(p.Id) as TotalPosts,
         avg(p.Score) as AvgScore,
         max(p.CreationDate) as LastPostDate,
         rank() over (order by u.Reputation desc nulls last) as RepRank
  from Users u
  left join Badges b on b.UserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
post_links_summary as (
  select pl.PostId,
         sum(case when lt.Name ilike 'Linked' then 1 else 0 end)    as linked_count,
         sum(case when lt.Name ilike 'Duplicate' then 1 else 0 end) as duplicate_count,
         count(*)                                                  as total_links
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId
),
answer_rank as (
  select a.Id,
         a.ParentId,
         a.Score,
         a.CreationDate,
         a.OwnerUserId,
         dense_rank() over (partition by a.ParentId order by coalesce(a.Score,0) desc, a.CreationDate asc) as rank_by_score,
         row_number() over (partition by a.ParentId order by a.CreationDate desc) as rn_recent
  from Posts a
  where a.PostTypeId = 2
),
top_answers as (
  select *
  from answer_rank
  where rank_by_score <= 3
),
question_metrics as (
  select q.Id as QuestionId,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score as QScore,
         q.ViewCount,
         q.AnswerCount,
         q.AcceptedAnswerId,
         pl.linked_count,
         pl.duplicate_count,
         coalesce((select count(*) from Comments c where c.PostId = q.Id and c.CreationDate <= q.CreationDate + interval '30 days'),0) as comments_first_30d,
         (select Text from Comments c2 where c2.PostId = q.Id order by c2.CreationDate desc limit 1) as last_comment_text,
         (select count(*) filter (where v.VoteTypeId = 2) from Votes v where v.PostId = q.Id) as upvotes,
         (select count(*) filter (where v.VoteTypeId = 3) from Votes v where v.PostId = q.Id) as downvotes,
         (case when q.ViewCount is null or q.ViewCount = 0 then null else round(q.Score::numeric / nullif(q.ViewCount,0),6) end) as score_per_view
  from question_posts q
  left join post_links_summary pl on pl.PostId = q.Id
),
moving_stats as (
  select qm.QuestionId,
         qm.Title,
         qm.CreationDate,
         qm.ViewCount,
         qm.QScore,
         e.Tag,
         avg(qm.ViewCount) over (partition by e.Tag order by qm.CreationDate rows between 10 preceding and 10 following) as local_avg_views,
         rank()   over (partition by e.Tag order by qm.ViewCount desc nulls last)             as tag_rank,
         row_number() over (partition by e.Tag order by qm.CreationDate desc nulls last)      as row_in_tag_by_time
  from question_metrics qm
  join exploded_tags e on e.QuestionId = qm.QuestionId
),
owner_lookup as (
  select u.Id, u.DisplayName, u.Reputation,
         coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1),0) as QuestionsPosted,
         coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2),0) as AnswersPosted
  from Users u
),
-- Two complementary report halves that will be combined using UNION ALL to stress set ops and grouping
question_report as (
  select
    'QUESTION'::varchar(10) as row_type,
    qm.QuestionId::text                               as key_id,
    left(coalesce(qm.Title,'(no title)'),200)         as headline,
    mt.Tag                                           as tag,
    round(mt.local_avg_views::numeric,2)             as metric_a,
    mt.tag_rank                                      as metric_b,
    to_char(qm.CreationDate,'YYYY-MM-DD')            as meta_date,
    left(coalesce(qm.last_comment_text,'(no recent comment)'),250) as meta_text,
    coalesce(
      nullif(string_agg(distinct concat('A#', ta.Id, ':S=', coalesce(ta.Score,0), ':R=', ta.rank_by_score) order by ta.rank_by_score asc, ' || '), ''),
      '(no answers)'
    ) as detail_text,
    coalesce(ol.DisplayName,'(unknown)')             as owner_display
  from moving_stats mt
  join question_metrics qm on qm.QuestionId = mt.QuestionId
  left join top_answers ta on ta.ParentId = qm.QuestionId
  left join owner_lookup ol on ol.Id = qm.OwnerUserId
  where mt.row_in_tag_by_time <= 50  -- limit window to recent per-tag rows, still stresses planner
  group by qm.QuestionId, qm.Title, mt.Tag, mt.local_avg_views, mt.tag_rank, qm.CreationDate, qm.last_comment_text, ol.DisplayName
),
user_report as (
  select
    'USER'::varchar(10) as row_type,
    us.UserId::text                                 as key_id,
    left(coalesce(us.DisplayName,'(anon)'),200)     as headline,
    null                                            as tag,
    round(coalesce(us.AvgScore,0)::numeric,4)       as metric_a,
    us.RepRank                                      as metric_b,
    to_char(us.LastPostDate,'YYYY-MM-DD')           as meta_date,
    concat('G:',coalesce(us.GoldBadges,0),' S:',coalesce(us.SilverBadges,0),' B:',coalesce(us.BronzeBadges,0)) as meta_text,
    coalesce(
      (select string_agg(distinct concat('T:', t.TagName, ':C=', t.Count), ' | ' order by t.Count desc) from Tags t where t.WikiPostId is not null limit 5),
      '(no tag wiki ties)'
    ) as detail_text,
    concat(coalesce(us.DisplayName,'(no name)'),' (rep=',coalesce(us.Reputation,0),')') as owner_display
  from user_stats us
  where us.TotalPosts > 0
  order by us.Reputation desc nulls last
  limit 200
)
-- Final combination uses set operator UNION ALL (a simple set op) and additional filtering using complex predicates
select *
from (
  select * from question_report
  union all
  select * from user_report
) combined
where
  -- complex predicate mixing NULL logic, regex, and arithmetic to further challenge optimizer
  (
    (row_type = 'QUESTION' and (metric_a is not null and metric_a > 10 or metric_b <= 5))
    or
    (row_type = 'USER' and (meta_text is not null and meta_text ~ 'G:[0-9]+'))
  )
and length(coalesce(headline,'')) > 3
order by row_type desc, metric_a nulls last, metric_b asc
limit 1000;