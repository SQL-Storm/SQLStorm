-- {"query": "597.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3843} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           u.upvotes,
           u.downvotes,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
tagged_questions as (
    select p.id as question_id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.favoritecount,
           p.commentcount,
           p.title,
           p.tags,
           regexp_split_to_table(coalesce(p.tags,''), '><') as raw_tag_piece
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
),
normalized_tags as (
    select tq.question_id,
           tq.owneruserid,
           tq.creationdate,
           tq.score,
           tq.viewcount,
           tq.answercount,
           tq.favoritecount,
           tq.commentcount,
           tq.title,
           case
             when tq.tags is null then null
             else trim(both '<>' from tq.raw_tag_piece)
           end as tag
    from tagged_questions tq
),
question_tag_stats as (
    select nt.question_id,
           count(*) filter (where nt.tag is not null) as tag_count,
           min(nt.tag) as first_tag_alpha,
           max(nt.tag) as last_tag_alpha
    from normalized_tags nt
    group by nt.question_id
),
user_activity as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as questions_posted,
           count(*) filter (where p.posttypeid = 2) as answers_posted,
           sum(coalesce(p.score,0)) as total_post_score,
           avg(nullif(p.score,0)) as avg_nonzero_post_score,
           count(distinct case when p.posttypeid = 1 then p.id end) filter (where p.acceptedanswerid is not null) as accepted_questions,
           count(distinct case when p.posttypeid = 2 and exists (
               select 1 from posts q where q.id = p.parentid and q.acceptedanswerid = p.id
           ) then p.id end) as accepted_answers
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comment_agg as (
    select c.postid,
           count(*) as comment_count,
           max(c.score) as max_comment_score,
           max(c.creationdate) as last_commented_at
    from comments c
    group by c.postid
),
closure_info as (
    select ph.postid,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (10,35)) as first_close_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (11)) as last_reopen_at,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
duplicate_links as (
    select pl.postid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_of_count,
           count(*) filter (where pl.linktypeid = 1) as linked_count,
           max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
badge_summary as (
    select b.userid,
           count(*) as badges_total,
           count(*) filter (where b.class = 1) as gold_count,
           count(*) filter (where b.class = 2) as silver_count,
           count(*) filter (where b.class = 3) as bronze_count,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
tag_popularity as (
    select lower(t.tagname) as tag,
           sum(t.count) as total_tag_count,
           max(t.count) as max_tag_count,
           count(*) as tag_rows
    from tags t
    group by lower(t.tagname)
),
question_rank as (
    select p.id as question_id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           qa.tag_count,
           coalesce(va.net_votes, 0) as net_votes,
           coalesce(ca.comment_count, 0) as comment_count,
           coalesce(qa.tag_count,0) + greatest(coalesce(va.upvotes,0) - coalesce(va.downvotes,0),0) as engagement_signal,
           row_number() over (
               partition by date_trunc('month', p.creationdate)
               order by coalesce(va.net_votes,0) + coalesce(p.score,0) + log(greatest(p.viewcount,1)) desc, p.id desc
           ) as monthly_rank
    from posts p
    left join question_tag_stats qa on qa.question_id = p.id
    left join vote_agg va on va.postid = p.id
    left join comment_agg ca on ca.postid = p.id
    where p.posttypeid = 1
),
top_questions as (
    select qr.*
    from question_rank qr
    where qr.monthly_rank <= 100
),
user_quality as (
    select u.id as user_id,
           u.displayname,
           coalesce(ua.questions_posted,0) as questions_posted,
           coalesce(ua.answers_posted,0) as answers_posted,
           coalesce(ua.total_post_score,0) as total_post_score,
           coalesce(ua.avg_nonzero_post_score,0) as avg_nonzero_post_score,
           coalesce(ua.accepted_questions,0) as accepted_questions,
           coalesce(ua.accepted_answers,0) as accepted_answers,
           coalesce(bs.badges_total,0) as badges_total,
           coalesce(bs.gold_count,0) as gold_count,
           coalesce(bs.silver_count,0) as silver_count,
           coalesce(bs.bronze_count,0) as bronze_count,
           coalesce(bs.tag_badges,0) as tag_badges,
           u.reputation,
           case
             when u.reputation >= 100000 then 'Legend'
             when u.reputation >= 20000 then 'Expert'
             when u.reputation >= 5000 then 'Advanced'
             when u.reputation >= 1000 then 'Intermediate'
             else 'Newbie'
           end as rep_bucket,
           greatest(coalesce(ua.total_post_score,0) + coalesce(bs.gold_count,0) * 50 + coalesce(bs.silver_count,0) * 10 + coalesce(bs.bronze_count,0) * 2, 0) as quality_score
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join badge_summary bs on bs.userid = u.id
),
owner_features as (
    select p.id as post_id,
           u.user_id,
           uq.quality_score,
           uq.rep_bucket,
           coalesce(u.location, 'Unknown') as location,
           coalesce(nullif(u.displayname,''), '(anonymous)') as displayname_norm
    from posts p
    left join users u on u.id = p.owneruserid
    left join user_quality uq on uq.user_id = u.id
),
question_tag_enriched as (
    select nt.question_id,
           string_agg(distinct nt.tag, '|' order by nt.tag) as tag_list,
           count(*) filter (where nt.tag is not null) as tag_count
    from normalized_tags nt
    group by nt.question_id
),
question_tag_popularity as (
    select nt.question_id,
           avg(tp.total_tag_count)::numeric(20,4) as avg_tag_popularity,
           max(tp.max_tag_count) as max_tag_popularity
    from normalized_tags nt
    left join tag_popularity tp on tp.tag = nt.tag
    group by nt.question_id
),
question_metrics as (
    select p.id as question_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.favoritecount,
           p.commentcount,
           oa.quality_score as owner_quality_score,
           oa.rep_bucket as owner_rep_bucket,
           oa.location as owner_location,
           qt.tag_list,
           qtp.avg_tag_popularity,
           qtp.max_tag_popularity,
           coalesce(va.net_votes,0) as net_votes,
           coalesce(va.upvotes,0) as upvotes,
           coalesce(va.downvotes,0) as downvotes,
           coalesce(ca.comment_count,0) as comment_count,
           ci.first_close_at,
           ci.last_reopen_at,
           ci.last_close_reason_id,
           dl.duplicate_of_count,
           dl.linked_count,
           tq.monthly_rank,
           case when p.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer
    from posts p
    left join owner_features oa on oa.post_id = p.id
    left join question_tag_enriched qt on qt.question_id = p.id
    left join question_tag_popularity qtp on qtp.question_id = p.id
    left join vote_agg va on va.postid = p.id
    left join comment_agg ca on ca.postid = p.id
    left join closure_info ci on ci.postid = p.id
    left join duplicate_links dl on dl.postid = p.id
    left join top_questions tq on tq.question_id = p.id
    where p.posttypeid = 1
),
score_buckets as (
    select qm.question_id,
           case
             when coalesce(qm.score,0) >= 1000 then 'S3: 1000+'
             when coalesce(qm.score,0) >= 100 then 'S2: 100-999'
             when coalesce(qm.score,0) >= 10 then 'S1: 10-99'
             when coalesce(qm.score,0) > 0 then 'S0: 1-9'
             when coalesce(qm.score,0) = 0 then 'S-: 0'
             else 'Sx: negative'
           end as score_bucket
    from question_metrics qm
),
view_percentiles as (
    select qm.question_id,
           ntile(100) over (order by coalesce(qm.viewcount,0)) as view_percentile
    from question_metrics qm
),
final_rank as (
    select qm.question_id,
           qm.creationdate,
           qm.score,
           qm.viewcount,
           qm.answercount,
           qm.favoritecount,
           qm.commentcount,
           qm.owner_quality_score,
           qm.owner_rep_bucket,
           qm.owner_location,
           qm.tag_list,
           qm.avg_tag_popularity,
           qm.max_tag_popularity,
           qm.net_votes,
           qm.upvotes,
           qm.downvotes,
           qm.first_close_at,
           qm.last_reopen_at,
           qm.last_close_reason_id,
           qm.duplicate_of_count,
           qm.linked_count,
           qm.monthly_rank,
           qm.has_accepted_answer,
           sb.score_bucket,
           vp.view_percentile,
           -- composite score mixes engagement, quality, and recency decay
           (
             0.5 * coalesce(qm.net_votes,0) +
             0.3 * coalesce(qm.score,0) +
             0.2 * log(greatest(qm.viewcount,1)) +
             case when qm.has_accepted_answer = 1 then 5 else 0 end +
             least(coalesce(qm.owner_quality_score,0) / 100.0, 20) +
             coalesce(qm.linked_count,0) * 0.5 -
             coalesce(qm.duplicate_of_count,0) * 1.5 -
             case when qm.first_close_at is not null and qm.last_reopen_at is null then 3 else 0 end
           )
           *
           exp(-extract(epoch from (now() - coalesce(qm.creationdate, now()))) / 60.0 / 60.0 / 24.0 / 365.0) as composite_score
    from question_metrics qm
    left join score_buckets sb on sb.question_id = qm.question_id
    left join view_percentiles vp on vp.question_id = qm.question_id
),
user_cross as (
    select r.user_id,
           r.displayname,
           r.reputation,
           r.creationdate,
           r.location,
           r.websiteurl,
           r.upvotes,
           r.downvotes,
           count(distinct p.id) as recent_posts,
           sum(coalesce(p.score,0)) as recent_score,
           sum(coalesce(p.viewcount,0)) as recent_views,
           avg(coalesce(p.score,0)) as recent_avg_score
    from recent_users r
    left join posts p on p.owneruserid = r.user_id
                     and p.creationdate >= r.creationdate
    group by r.user_id, r.displayname, r.reputation, r.creationdate, r.location, r.websiteurl, r.upvotes, r.downvotes
),
ranked_output as (
    select fr.*,
           dense_rank() over (order by fr.composite_score desc nulls last) as global_rank
    from final_rank fr
),
labelled_close_reason as (
    select ci.postid,
           crt.name as close_reason_name
    from closure_info ci
    left join closerreasontypes crt on crt.id = ci.last_close_reason_id
),
title_signal as (
    select p.id as post_id,
           length(coalesce(p.title,'')) as title_len,
           case when position('?' in coalesce(p.title,'')) > 0 then 1 else 0 end as has_question_mark,
           regexp_count(coalesce(p.title,''), '\b(how|why|what|where|when|can|should)\b', 'i') as wh_words
    from posts p
    where p.posttypeid = 1
),
body_signal as (
    select p.id as post_id,
           length(coalesce(p.body,'')) as body_len,
           regexp_count(coalesce(p.body,''), '<code>', 'i') as code_blocks,
           regexp_count(coalesce(p.body,''), '\b(error|exception|fail(ed|ure)?|null|pointer|timeout|crash)\b', 'i') as error_terms
    from posts p
    where p.posttypeid = 1
),
signals as (
    select ts.post_id,
           ts.title_len,
           ts.has_question_mark,
           ts.wh_words,
           bs.body_len,
           bs.code_blocks,
           bs.error_terms,
           case
               when bs.code_blocks > 0 then 'HasCode'
               when ts.wh_words >= 2 then 'ManyWH'
               when ts.has_question_mark = 1 then 'QuestionMark'
               else 'Other'
           end as content_class
    from title_signal ts
    full outer join body_signal bs on bs.post_id = ts.post_id
)
select ro.global_rank,
       ro.question_id,
       p.title,
       p.owneruserid,
       coalesce(u.displayname, p.ownerdisplayname, '(unknown)') as owner_name,
       ro.composite_score,
       ro.score,
       ro.net_votes,
       ro.viewcount,
       ro.answercount,
       ro.favoritecount,
       ro.commentcount,
       ro.owner_quality_score,
       ro.owner_rep_bucket,
       ro.owner_location,
       coalesce(qt.tag_list, '(none)') as tag_list,
       ro.avg_tag_popularity,
       ro.max_tag_popularity,
       ro.first_close_at,
       lcr.close_reason_name,
       ro.duplicate_of_count,
       ro.linked_count,
       ro.monthly_rank,
       ro.has_accepted_answer,
       ro.score_bucket,
       ro.view_percentile,
       s.title_len,
       s.body_len,
       s.code_blocks,
       s.error_terms,
       s.content_class,
       uc.recent_posts,
       uc.recent_score,
       uc.recent_views,
       uc.recent_avg_score
from ranked_output ro
left join posts p on p.id = ro.question_id
left join users u on u.id = p.owneruserid
left join question_tag_enriched qt on qt.question_id = ro.question_id
left join labelled_close_reason lcr on lcr.postid = ro.question_id
left join signals s on s.post_id = ro.question_id
left join user_cross uc on uc.user_id = p.owneruserid
where ro.global_rank <= 1000
  and (
      u.location is null
      or u.location ilike any (array['%USA%','%United States%','%UK%','%Canada%','%India%','%Germany%'])
      or ro.viewcount > 1000
  )
  and not (p.communityowneddate is not null and p.owneruserid = -1)
  and coalesce(ro.score,0) + coalesce(ro.net_votes,0) + coalesce(ro.linked_count,0) - coalesce(ro.duplicate_of_count,0) >= -10
order by ro.global_rank, ro.question_id;