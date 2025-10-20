-- {"query": "38038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2075} 
with recent_users as (
    select u.id as user_id, u.displayname, u.reputation, u.creationdate
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
hot_questions as (
    select p.id as question_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.owneruserid,
           p.title,
           p.tags,
           coalesce(p.answercount, 0) as answercount
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
      and (p.score >= 5 or p.viewcount >= 1000 or coalesce(p.answercount,0) >= 3)
),
answers as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid,
           a.score as answer_score,
           a.creationdate as answer_date
    from posts a
    where a.posttypeid = 2
      and a.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 2)
),
accepted as (
    select q.id as question_id, q.acceptedanswerid
    from posts q
    where q.posttypeid = 1
      and q.acceptedanswerid is not null
),
comment_activity as (
    select c.postid as post_id,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as upcomment_count,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
    group by c.postid
),
vote_agg as (
    select v.postid as post_id,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
tag_expanded as (
    select hq.question_id,
           unnest(string_to_array(substring(hq.tags, 2, length(hq.tags)-2), '><')) as tag
    from hot_questions hq
    where hq.tags is not null and hq.tags like '<%>'
),
tag_stats as (
    select te.tag,
           count(distinct te.question_id) as question_count,
           sum(hq.viewcount) as total_views,
           avg(hq.score) as avg_score
    from tag_expanded te
    join hot_questions hq on hq.question_id = te.question_id
    group by te.tag
    having count(distinct te.question_id) >= 5
),
linked_dupes as (
    select pl.postid as question_id,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
           max(pl.creationdate) as last_link_date
    from postlinks pl
    where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
    group by pl.postid
),
edits as (
    select ph.postid as post_id,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
           count(*) filter (where ph.posthistorytypeid in (10)) as close_events,
           count(*) filter (where ph.posthistorytypeid in (11)) as reopen_events,
           max(ph.creationdate) as last_history_date
    from posthistory ph
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
    group by ph.postid
),
answer_agg as (
    select a.question_id,
           count(*) as answers_last_year,
           max(a.answer_score) as max_answer_score,
           avg(a.answer_score) as avg_answer_score,
           count(*) filter (where a.owneruserid in (select user_id from recent_users)) as answers_by_new_users
    from answers a
    group by a.question_id
),
accepted_flags as (
    select ac.question_id,
           1 as has_accepted
    from accepted ac
),
owner_stats as (
    select u.id as owner_id,
           u.reputation,
           u.views,
           u.upvotes,
           u.downvotes,
           u.creationdate as user_created
    from users u
),
question_owner as (
    select hq.question_id, hq.title, hq.creationdate as question_date, hq.viewcount, hq.score, hq.answercount,
           hq.owneruserid as owner_id
    from hot_questions hq
),
badge_counts as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           count(*) as total_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_rank as (
    select ts.tag,
           ts.question_count,
           ts.total_views,
           ts.avg_score,
           row_number() over (order by ts.total_views desc) as tag_popularity_rank
    from tag_stats ts
),
q_tag_top as (
    select te.question_id,
           min(tr.tag) filter (where tr.tag_popularity_rank <= 10) as top_tag_sample
    from tag_expanded te
    join tag_rank tr on tr.tag = te.tag
    group by te.question_id
)
select
    qo.question_id,
    qo.title,
    qo.question_date,
    qo.viewcount,
    qo.score as question_score,
    qa.answers_last_year,
    qa.max_answer_score,
    qa.avg_answer_score,
    coalesce(af.has_accepted, 0) as has_accepted_answer,
    coalesce(ca.comment_count, 0) as comments_last_year,
    coalesce(ca.upcomment_count, 0) as positive_comments_last_year,
    coalesce(va.upvotes, 0) as upvotes_last_year,
    coalesce(va.downvotes, 0) as downvotes_last_year,
    coalesce(va.favorites, 0) as favorites_last_year,
    coalesce(va.bounty_total, 0) as bounty_last_year,
    coalesce(ld.linked_count, 0) as links_last_year,
    coalesce(ld.duplicate_count, 0) as duplicate_links_last_year,
    coalesce(ed.edit_count, 0) as edits_last_year,
    coalesce(ed.close_events, 0) as closes_last_year,
    coalesce(ed.reopen_events, 0) as reopens_last_year,
    ou.displayname as owner_displayname,
    os.reputation as owner_reputation,
    os.upvotes as owner_upvotes,
    os.downvotes as owner_downvotes,
    os.user_created as owner_creationdate,
    coalesce(bc.gold_badges, 0) as owner_gold_badges,
    coalesce(bc.silver_badges, 0) as owner_silver_badges,
    coalesce(bc.bronze_badges, 0) as owner_bronze_badges,
    coalesce(bc.total_badges, 0) as owner_total_badges,
    qt.top_tag_sample as sample_top_tag,
    greatest(
        coalesce(ca.last_comment_date, timestamp 'epoch'),
        coalesce(va.last_vote_date, timestamp 'epoch'),
        coalesce(ld.last_link_date, timestamp 'epoch'),
        coalesce(ed.last_history_date, timestamp 'epoch'),
        qo.question_date
    ) as last_activity_any,
    row_number() over (
        partition by (qt.top_tag_sample is not null)
        order by
            coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc,
            coalesce(qa.answers_last_year,0) desc,
            qo.viewcount desc
    ) as bench_rank
from question_owner qo
left join answer_agg qa on qa.question_id = qo.question_id
left join accepted_flags af on af.question_id = qo.question_id
left join comment_activity ca on ca.post_id = qo.question_id
left join vote_agg va on va.post_id = qo.question_id
left join linked_dupes ld on ld.question_id = qo.question_id
left join edits ed on ed.post_id = qo.question_id
left join users ou on ou.id = qo.owner_id
left join owner_stats os on os.owner_id = qo.owner_id
left join badge_counts bc on bc.user_id = qo.owner_id
left join q_tag_top qt on qt.question_id = qo.question_id
where qo.question_date >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
qualify bench_rank <= 500
order by bench_rank, last_activity_any desc, qo.viewcount desc;