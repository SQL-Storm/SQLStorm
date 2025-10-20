with
-- high-activity questions in last year with tag parsing and derived metrics
RecentQuestions as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    p.viewcount,
    p.score,
    p.answercount,
    coalesce(p.tags,'') as raw_tags,
    regexp_split_to_table(trim(both '<>' from replace(coalesce(p.tags,''), '><', '><')), '><') as single_tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '365 days')
),
-- per-question aggregates: best answer, average comment score, distinct voters, last edit gap
QuestionStats as (
  select
    q.id,
    q.title,
    q.creationdate,
    q.owneruserid,
    q.viewcount,
    q.score,
    q.answercount,
    q.raw_tags,
    count(distinct v.userid) filter (where v.votetypeid in (2,3)) as distinct_voters,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as vote_balance,
    (select max(a.score) from posts a where a.parentid = q.id and a.posttypeid = 2) as best_answer_score,
    (select count(*) from comments c where c.postid = q.id) as comments_on_question,
    (select avg(coalesce(c.score,0)) from comments c where c.postid = q.id) as avg_comment_score,
    greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - coalesce(pst.lasteditdate,pst.creationdate))),0) as seconds_since_last_edit
  from RecentQuestions q
  left join votes v on v.postid = q.id
  left join posts pst on pst.id = q.id
  group by q.id, q.title, q.creationdate, q.owneruserid, q.viewcount, q.score, q.answercount, q.raw_tags, pst.lasteditdate, pst.creationdate
),
-- windowed ranking across questions and users
QuestionRankings as (
  select
    qs.id,
    qs.title,
    qs.creationdate,
    qs.owneruserid,
    qs.viewcount,
    qs.score,
    qs.answercount,
    qs.raw_tags,
    qs.distinct_voters,
    qs.vote_balance,
    qs.best_answer_score,
    qs.comments_on_question,
    qs.avg_comment_score,
    qs.seconds_since_last_edit,
    dense_rank() over (order by (coalesce(qs.best_answer_score,0) * 3 + qs.vote_balance * 2 + qs.viewcount / nullif(greatest(qs.seconds_since_last_edit,1),1)) desc) as hotness_rank,
    row_number() over (partition by qs.owneruserid order by qs.creationdate desc) as owner_question_sequence
  from QuestionStats qs
),
-- users summary with correlated subqueries
UserSummary as (
  select u.id as userid,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         (select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 1) as questions_asked,
         (select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 2) as answers_posted,
         (select count(distinct b.name) from badges b where b.userid = u.id) as distinct_badges,
         coalesce((select sum(case when v.votetypeid=2 then 1 when v.votetypeid=3 then -1 else 0 end) from votes v join posts p on p.id=v.postid where p.owneruserid=u.id),0) as net_votes_on_posts,
         (select max(p.score) from posts p where p.owneruserid = u.id) as max_post_score,
         (select bool_or(p.communityowneddate is not null) from posts p where p.owneruserid = u.id) as any_community_owned
  from users u
  where u.creationdate <= cast('2024-10-01 12:34:56' as timestamp)
),
-- tags heatmap joined to questions
TagHeat as (
  select
    t.tagname,
    count(distinct q.id) as question_count,
    sum(q.viewcount) as total_views,
    avg(q.score) as avg_score,
    max(q.answercount) as max_answers,
    (array_agg(q.id ORDER BY q.score DESC NULLS LAST))[1:3] as top_question_ids
  from tags t
  left join (
    select distinct id, raw_tags, viewcount, score, answercount
    from QuestionStats
  ) q on position('<' || t.tagname || '>' in coalesce(q.raw_tags,'')) > 0
  group by t.tagname
),
-- combine for heavy-weight report: include correlated subqueries for related posts and links
HeavyReport as (
  select
    qr.id as question_id,
    qr.title,
    qr.creationdate,
    qr.owneruserid,
    us.displayname as owner_name,
    us.reputation as owner_reputation,
    qr.viewcount,
    qr.score,
    qr.answercount,
    qr.best_answer_score,
    qr.distinct_voters,
    qr.vote_balance,
    qr.hotness_rank,
    qr.owner_question_sequence,
    (left(coalesce(qr.title,''), 80) || ' :: tags=' || coalesce(qr.raw_tags,'<none>') || ' :: vb=' || coalesce(cast(qr.vote_balance as varchar),'0')) as signature,
    (select count(*) from postlinks pl where pl.postid = qr.id and pl.linktypeid = 3) as duplicate_links_out,
    (select count(*) from postlinks pl where pl.relatedpostid = qr.id and pl.linktypeid = 3) as duplicate_links_in,
    (select ph.creationdate from posthistory ph where ph.postid = qr.id order by ph.creationdate desc limit 1) as last_history_date,
    (select ph.posthistorytypeid from posthistory ph where ph.postid = qr.id order by ph.creationdate desc limit 1) as last_history_type,
    (select string_agg(s, ';') from (
       select coalesce(c.userdisplayname, 'anon') || ':' || coalesce(cast(c.score as varchar),'0') as s
       from comments c
       where c.postid = qr.id
       order by c.score desc
       limit 5
    ) x) as top_commenters,
    (case
       when qr.best_answer_score is null and qr.answercount = 0 then 'unanswered'
       when qr.best_answer_score is null then 'answers_no_scores'
       when qr.best_answer_score >= 50 then 'has_high_scoring_answer'
       when qr.vote_balance < 0 then 'controversial'
       else 'normal'
     end) as status_tag
  from QuestionRankings qr
  left join UserSummary us on us.userid = qr.owneruserid
)
select
  hr.*,
  th.tagname,
  th.question_count,
  th.total_views,
  th.avg_score,
  th.max_answers,
  th.top_question_ids
from HeavyReport hr
left join TagHeat th on position('<' || th.tagname || '>' in coalesce((select qs.raw_tags from QuestionStats qs where qs.id = hr.question_id),'')) > 0
where
  (hr.hotness_rank <= 250 or hr.viewcount > 10000 or hr.owner_reputation > 10000)
  and (hr.status_tag <> 'unanswered' or hr.answercount > 0)
  and (coalesce(hr.last_history_type,0) not in (12,10)
       or hr.last_history_date is null)
order by hr.hotness_rank, hr.viewcount desc
limit 500;