-- {"query": "819.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3247} 
with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    p.title,
    p.tags,
    coalesce(p.answercount, 0) as answercount,
    coalesce(p.commentcount, 0) as commentcount,
    coalesce(p.favoritecount, 0) as favoritecount,
    u.displayname as owner_name,
    u.reputation as owner_rep,
    case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end), 0) as net_votes_cast,
    coalesce(sum(case when b.class = 1 then 1 else 0 end), 0) as gold_badges,
    coalesce(sum(case when b.class = 2 then 1 else 0 end), 0) as silver_badges,
    coalesce(sum(case when b.class = 3 then 1 else 0 end), 0) as bronze_badges,
    count(distinct p.id) filter (where p.owneruserid = u.id) as posts_authored
  from users u
  left join votes v on v.userid = u.id and v.creationdate >= u.creationdate
  left join badges b on b.userid = u.id
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
question_metrics as (
  select
    q.id as question_id,
    q.creationdate,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount as q_answers,
    q.commentcount as q_comments,
    q.favoritecount as q_favs,
    q.owneruserid as asker_id,
    q.acceptedanswerid,
    q.tags,
    regexp_replace(coalesce(q.title, ''), '\s+', ' ', 'g') as normalized_title,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    array_length(string_to_array(coalesce(nullif(trim(both '<>' from q.tags), ''), ''), '><'), 1) as tag_count
  from posts q
  where q.posttypeid = 1
),
answer_metrics as (
  select
    a.parentid as question_id,
    count(*) as answers_total,
    max(a.score) as max_answer_score,
    avg(a.score) filter (where a.score is not null) as avg_answer_score,
    count(*) filter (where a.creationdate <= q.creationdate + interval '1 day') as answers_day1
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
  group by a.parentid
),
comment_sentiment as (
  select
    c.postid as post_id,
    avg(c.score) as avg_comment_score,
    sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_count,
    sum(case when position('please' in lower(c.text)) > 0 then 1 else 0 end) as please_count,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
close_reasons as (
  select
    ph.postid as post_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_raw
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select
    pl.postid as post_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  group by pl.postid
),
vote_rollup as (
  select
    v.postid as post_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_votes,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.postid
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tag
  from question_metrics q
),
tag_stats as (
  select
    te.question_id,
    count(*) as tag_count,
    sum(t.count) as tag_popularity_sum,
    avg(t.count) as tag_popularity_avg,
    sum(case when t.ismoderatoronly then 1 else 0 end) as mod_only_tags,
    sum(case when t.isrequired then 1 else 0 end) as required_tags
  from tag_expansion te
  left join tags t on lower(t.tagname) = lower(te.tag)
  group by te.question_id
),
owner_engagement as (
  select
    q.id as question_id,
    sum(case when c.userid = q.owneruserid then 1 else 0 end) as owner_comments_on_question,
    sum(case when c.userid is null and c.userdisplayname is not null then 1 else 0 end) as anon_comments
  from posts q
  left join comments c on c.postid = q.id
  where q.posttypeid = 1
  group by q.id
),
activity_windows as (
  select
    p.id as post_id,
    p.creationdate,
    count(*) filter (where v.creationdate <= p.creationdate + interval '1 day') as votes_day1,
    count(*) filter (where v.creationdate <= p.creationdate + interval '7 days') as votes_week1,
    count(*) filter (where v.creationdate <= p.creationdate + interval '30 days') as votes_month1
  from posts p
  left join votes v on v.postid = p.id
  where p.posttypeid in (1,2)
  group by p.id, p.creationdate
),
user_rank as (
  select
    ua.user_id,
    ua.displayname,
    ua.reputation,
    row_number() over (order by ua.reputation desc, ua.posts_authored desc) as rep_rank_global,
    ntile(100) over (order by ua.reputation desc) as rep_percentile
  from user_activity ua
),
question_quality as (
  select
    q.question_id,
    q.asker_id,
    q.q_score,
    q.q_views,
    coalesce(ar.answers_total, 0) as answers_total,
    coalesce(ar.max_answer_score, 0) as max_answer_score,
    coalesce(ar.avg_answer_score, 0) as avg_answer_score,
    coalesce(vr.upvotes, 0) as upvotes,
    coalesce(vr.downvotes, 0) as downvotes,
    coalesce(vr.bounty_total, 0) as bounty_total,
    coalesce(cs.avg_comment_score, 0) as avg_comment_score,
    coalesce(cs.thanks_count, 0) as thanks_count,
    coalesce(cs.please_count, 0) as please_count,
    coalesce(ts.tag_popularity_avg, 0) as tag_popularity_avg,
    coalesce(ts.mod_only_tags, 0) as mod_only_tags,
    coalesce(ts.required_tags, 0) as required_tags,
    coalesce(dw.votes_day1, 0) as votes_day1,
    coalesce(dw.votes_week1, 0) as votes_week1,
    coalesce(dw.votes_month1, 0) as votes_month1,
    coalesce(dl.duplicate_links, 0) as duplicate_links,
    coalesce(dl.related_links, 0) as related_links,
    case
      when q.q_views is null or q.q_views = 0 then null
      else round((q.q_score::numeric + coalesce(ar.answers_total,0) + coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0)) / nullif(q.q_views,0), 6)
    end as engagement_ratio
  from question_metrics q
  left join answer_metrics ar on ar.question_id = q.question_id
  left join vote_rollup vr on vr.post_id = q.question_id
  left join comment_sentiment cs on cs.post_id = q.question_id
  left join tag_stats ts on ts.question_id = q.question_id
  left join activity_windows dw on dw.post_id = q.question_id
  left join dup_links dl on dl.post_id = q.question_id
),
accepted_answer_latency as (
  select
    q.id as question_id,
    case
      when q.acceptedanswerid is null then null
      else (
        select a.creationdate - q.creationdate
        from posts a
        where a.id = q.acceptedanswerid
      )
    end as time_to_accept
  from posts q
  where q.posttypeid = 1
),
owner_history as (
  select
    ph.postid as post_id,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    count(*) filter (where ph.posthistorytypeid in (12)) as deletions_votes,
    count(*) filter (where ph.posthistorytypeid in (11)) as undeletions_votes
  from posthistory ph
  group by ph.postid
),
final_scored as (
  select
    qq.question_id,
    qq.asker_id,
    ua.displayname as asker_name,
    ur.rep_rank_global,
    ur.rep_percentile,
    qq.q_score,
    qq.q_views,
    qq.engagement_ratio,
    qq.answers_total,
    qq.max_answer_score,
    qq.avg_answer_score,
    qq.upvotes,
    qq.downvotes,
    qq.bounty_total,
    qq.avg_comment_score,
    qq.thanks_count,
    qq.please_count,
    qq.tag_popularity_avg,
    qq.mod_only_tags,
    qq.required_tags,
    qq.votes_day1,
    qq.votes_week1,
    qq.votes_month1,
    al.time_to_accept,
    oh.first_edit_at,
    oh.edit_count,
    oh.suggested_edits_applied,
    oh.deletions_votes,
    oh.undeletions_votes,
    cr.last_closed_at,
    cr.last_close_reason_raw,
    dl.duplicate_links,
    dl.related_links,
    case
      when qq.engagement_ratio is null then 0
      else qq.engagement_ratio
    end
    + coalesce(qq.avg_comment_score,0) * 0.01
    + coalesce(qq.bounty_total,0) * 0.0001
    + coalesce(qq.votes_day1,0) * 0.02
    + coalesce(qq.votes_week1,0) * 0.01
    - coalesce(qq.downvotes,0) * 0.01
    - case when cr.last_closed_at is not null then 0.5 else 0 end
    + case when al.time_to_accept is not null and al.time_to_accept <= interval '1 day' then 0.1 else 0 end
    - coalesce(dl.duplicate_links,0) * 0.05
    + case when ur.rep_percentile <= 10 then 0.05 else 0 end
    as quality_score
  from question_quality qq
  left join accepted_answer_latency al on al.question_id = qq.question_id
  left join owner_history oh on oh.post_id = qq.question_id
  left join close_reasons cr on cr.post_id = qq.question_id
  left join dup_links dl on dl.post_id = qq.question_id
  left join users ua on ua.id = qq.asker_id
  left join user_rank ur on ur.user_id = qq.asker_id
),
dedup as (
  select
    fs.*,
    row_number() over (
      partition by fs.asker_id
      order by fs.quality_score desc, fs.q_views desc, fs.q_score desc
    ) as rn_best_per_user
  from final_scored fs
)
select
  d.question_id,
  d.asker_id,
  coalesce(d.asker_name, '(unknown)') as asker_name,
  d.rep_rank_global,
  d.rep_percentile,
  d.q_score,
  d.q_views,
  d.engagement_ratio,
  d.answers_total,
  d.max_answer_score,
  round(coalesce(d.avg_answer_score,0), 3) as avg_answer_score,
  d.upvotes,
  d.downvotes,
  d.bounty_total,
  round(coalesce(d.avg_comment_score,0), 3) as avg_comment_score,
  d.thanks_count,
  d.please_count,
  round(coalesce(d.tag_popularity_avg,0), 3) as tag_popularity_avg,
  d.mod_only_tags,
  d.required_tags,
  d.votes_day1,
  d.votes_week1,
  d.votes_month1,
  d.time_to_accept,
  d.first_edit_at,
  d.edit_count,
  d.suggested_edits_applied,
  d.deletions_votes,
  d.undeletions_votes,
  d.last_closed_at,
  d.last_close_reason_raw,
  d.duplicate_links,
  d.related_links,
  round(d.quality_score::numeric, 6) as quality_score,
  case
    when d.q_views is null then 'no views'
    when d.q_views = 0 then 'zero views'
    when d.q_views < 100 then 'low views'
    when d.q_views < 1000 then 'medium views'
    else 'high views'
  end as view_bucket
from dedup d
where d.rn_best_per_user <= 3
order by d.quality_score desc nulls last, d.q_views desc, d.q_score desc
limit 500;