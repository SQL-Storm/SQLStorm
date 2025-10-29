-- {"query": "507.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3345}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
top_users as (
    select *
    from recent_users
    where rn <= 500
),
q as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount as q_views,
        p.tags,
        p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select date_trunc('year', min(creationdate)) from users)
),
a as (
    select
        p.id as answer_id,
        p.parentid as question_id,
        p.owneruserid as answerer_id,
        p.creationdate as a_created,
        p.score as a_score
    from posts p
    where p.posttypeid = 2
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
badges_agg as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) as total_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
postlinks_dupe as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as dupes_out,
        count(*) filter (where pl.linktypeid = 1) as linked_out
    from postlinks pl
    group by pl.postid
),
close_events as (
    select
        ph.postid as question_id,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
        count(*) filter (where ph.posthistorytypeid = 11) as reopens,
        max(nullif(ph.comment, '')) as last_close_reason_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
accept_answer_latency as (
    select
        q.question_id,
        case
            when q.acceptedanswerid is null then null
            else (select a2.a_created from a a2 where a2.answer_id = q.acceptedanswerid)
        end as accepted_at
    from q
),
first_answer as (
    select
        a.question_id,
        min(a.a_created) as first_answer_at,
        count(*) as answer_count,
        sum(case when a.a_score > 0 then 1 else 0 end) as pos_answers
    from a
    group by a.question_id
),
answerer_mix as (
    select
        a.question_id,
        count(distinct a.answerer_id) as distinct_answerers,
        count(distinct case when a.a_score >= 5 then a.answerer_id end) as distinct_highrep_answerers
    from a
    group by a.question_id
),
question_activity as (
    select
        q.question_id,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.q_views,
        q.tags,
        fa.first_answer_at,
        aa.accepted_at,
        greatest(q.q_created,
                 coalesce(fa.first_answer_at, q.q_created),
                 coalesce(ca.last_comment_at, q.q_created)) as last_seen_activity,
        coalesce(vq.upvotes,0) as q_up,
        coalesce(vq.downvotes,0) as q_down,
        coalesce(vq.favorites,0) as q_fav,
        coalesce(vq.bounty_total,0) as q_bounty,
        coalesce(ca.comment_count,0) as q_comments,
        coalesce(ca.pos_comments,0) as q_pos_comments,
        coalesce(pl.dupes_out,0) as dupes_out,
        coalesce(pl.linked_out,0) as linked_out,
        coalesce(ce.first_closed_at, null) as first_closed_at,
        coalesce(ce.last_reopened_at, null) as last_reopened_at,
        ce.close_votes,
        ce.reopens,
        ce.last_close_reason_raw
    from q
    left join first_answer fa on fa.question_id = q.question_id
    left join accept_answer_latency aa on aa.question_id = q.question_id
    left join comments_agg ca on ca.postid = q.question_id
    left join votes_agg vq on vq.postid = q.question_id
    left join postlinks_dupe pl on pl.question_id = q.question_id
    left join close_events ce on ce.question_id = q.question_id
),
answer_activity as (
    select
        a.question_id,
        sum(coalesce(va.upvotes,0)) as a_up,
        sum(coalesce(va.downvotes,0)) as a_down,
        sum(coalesce(va.favorites,0)) as a_fav,
        sum(coalesce(va.bounty_total,0)) as a_bounty,
        sum(coalesce(cc.comment_count,0)) as a_comments,
        sum(case when a.a_score >= 1 then 1 else 0 end) as answers_nonneg,
        max(a.a_score) as max_answer_score
    from a
    left join votes_agg va on va.postid = a.answer_id
    left join comments_agg cc on cc.postid = a.answer_id
    group by a.question_id
),
user_enrichment as (
    select
        tu.user_id,
        tu.displayname,
        tu.reputation,
        tu.location,
        tu.websiteurl,
        coalesce(ba.gold_cnt,0) as gold_cnt,
        coalesce(ba.silver_cnt,0) as silver_cnt,
        coalesce(ba.bronze_cnt,0) as bronze_cnt,
        coalesce(ba.total_badges,0) as total_badges,
        ba.last_badge_at
    from top_users tu
    left join badges_agg ba on ba.userid = tu.user_id
),
questioner_stats as (
    select
        qa.question_id,
        ue.user_id as asker_id,
        ue.displayname as asker_name,
        ue.reputation as asker_rep,
        ue.location as asker_loc,
        ue.websiteurl as asker_web,
        ue.gold_cnt as asker_gold,
        ue.silver_cnt as asker_silver,
        ue.bronze_cnt as asker_bronze,
        ue.total_badges as asker_badges
    from question_activity qa
    left join user_enrichment ue on ue.user_id = qa.asker_id
),
tag_expansion as (
    select
        qa.question_id,
        unnest(string_to_array(substring(qa.tags, 2, greatest(length(qa.tags)-2,0)), '><')) as tag
    from question_activity qa
),
tag_rank as (
    select
        te.question_id,
        te.tag,
        t.count as global_tag_count,
        dense_rank() over (partition by te.question_id order by coalesce(t.count,0) desc, te.tag) as tag_pop_rank
    from tag_expansion te
    left join tags t on t.tagname = te.tag
),
accepted_vs_top as (
    select
        qa.question_id,
        qa.accepted_at,
        fa.first_answer_at,
        case
            when qa.accepted_at is null then null
            else cast(extract(epoch from (qa.accepted_at - qa.q_created)) as bigint)
        end as secs_to_accept,
        case
            when fa.first_answer_at is null then null
            else cast(extract(epoch from (fa.first_answer_at - qa.q_created)) as bigint)
        end as secs_to_first_answer,
        case
            when qa.accepted_at is not null and fa.first_answer_at is not null
                 and qa.accepted_at <= fa.first_answer_at + interval '10 minutes'
            then 1 else 0
        end as accepted_near_first_flag
    from question_activity qa
    left join first_answer fa on fa.question_id = qa.question_id
),
ranked_questions as (
    select
        qa.*,
        coalesce(aa.a_up,0) as a_up,
        coalesce(aa.a_down,0) as a_down,
        coalesce(aa.a_fav,0) as a_fav,
        coalesce(aa.a_bounty,0) as a_bounty,
        coalesce(aa.a_comments,0) as a_comments,
        coalesce(aa.answers_nonneg,0) as answers_nonneg,
        coalesce(aa.max_answer_score, null) as max_answer_score,
        coalesce(am.distinct_answerers,0) as distinct_answerers,
        coalesce(am.distinct_highrep_answerers,0) as distinct_highrep_answerers,
        av.secs_to_accept,
        av.secs_to_first_answer,
        av.accepted_near_first_flag,
        row_number() over (
            order by
                (coalesce(qa.q_up,0) - coalesce(qa.q_down,0) + coalesce(aa.a_up,0) - coalesce(aa.a_down,0)) desc,
                qa.q_views desc,
                qa.q_created desc
        ) as hot_rank
    from question_activity qa
    left join answer_activity aa on aa.question_id = qa.question_id
    left join answerer_mix am on am.question_id = qa.question_id
    left join accepted_vs_top av on av.question_id = qa.question_id
),
topk as (
    select *
    from ranked_questions
    where hot_rank <= 300
),
tag_choices as (
    select
        tr.question_id,
        string_agg(tc.tag, ', ' order by tr.tag_pop_rank, tc.tag) filter (where tr.tag_pop_rank <= 3) as top3_tags,
        string_agg(tc.tag, ', ' order by tc.tag) as all_tags
    from tag_rank tr
    join tag_expansion tc on tc.question_id = tr.question_id and tc.tag = tr.tag
    group by tr.question_id
),
stringified as (
    select
        tk.question_id,
        tk.asker_id,
        coalesce(qs.asker_name, concat('user#', cast(tk.asker_id as text))) as asker_name,
        tk.q_created,
        tk.q_score,
        tk.q_views,
        coalesce(tc.top3_tags, '(no tags)') as top3_tags,
        coalesce(tc.all_tags, '(no tags)') as all_tags,
        concat_ws(
            ' | ',
            'QScore=' || coalesce(tk.q_score,0),
            'NetVotes=' || (coalesce(tk.q_up,0) - coalesce(tk.q_down,0) + coalesce(tk.a_up,0) - coalesce(tk.a_down,0)),
            'Views=' || coalesce(tk.q_views,0),
            'Answers=' || coalesce((select answer_count from first_answer fa where fa.question_id = tk.question_id), 0),
            'Comments=' || coalesce(tk.q_comments,0),
            'Bounty=' || coalesce(tk.q_bounty,0)
        ) as metrics_str,
        concat_ws(
            ' | ',
            'AcceptedIn=' || coalesce(cast(tk.secs_to_accept as text), 'NA'),
            'FirstAnsIn=' || coalesce(cast(tk.secs_to_first_answer as text), 'NA'),
            'NearFirst=' || case when tk.accepted_near_first_flag = 1 then 'Y' else 'N' end
        ) as timing_str
    from topk tk
    left join questioner_stats qs on qs.question_id = tk.question_id
    left join tag_choices tc on tc.question_id = tk.question_id
),
null_logic as (
    select
        s.*,
        case
            when s.q_views is null or s.q_views = 0 then 'low-visibility'
            when s.q_views between 1 and 999 then 'visible'
            when s.q_views between 1000 and 9999 then 'popular'
            else 'viral'
        end as visibility_bucket,
        case
            when s.q_score is null then 'unknown'
            when s.q_score < 0 then 'controversial'
            when s.q_score = 0 then 'neutral'
            when s.q_score between 1 and 4 then 'liked'
            else 'loved'
        end as sentiment_bucket
    from stringified s
),
dupe_overlay as (
    select
        nl.question_id,
        count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
    from null_logic nl
    left join postlinks pl on pl.postid = nl.question_id
    group by nl.question_id
)
select
    nl.question_id,
    nl.asker_id,
    nl.asker_name,
    nl.q_created,
    nl.q_score,
    nl.q_views,
    nl.top3_tags,
    nl.all_tags,
    nl.metrics_str,
    nl.timing_str,
    nl.visibility_bucket,
    nl.sentiment_bucket,
    coalesce(d.distinct_dupe_targets,0) as distinct_dupe_targets,
    (
        select concat_ws(
            ' | ',
            'AnsBy=' || coalesce(u.displayname, concat('user#', cast(a.owneruserid as text))),
            'Rep=' || coalesce(cast(u.reputation as text), '0'),
            'Badges=' || coalesce(cast(ba.total_badges as text), '0')
        )
        from posts a
        left join users u on u.id = a.owneruserid
        left join badges_agg ba on ba.userid = u.id
        where a.id = (select p.acceptedanswerid from posts p where p.id = nl.question_id)
        limit 1
    ) as accepted_answer_author
from null_logic nl
left join dupe_overlay d on d.question_id = nl.question_id
where (
        nl.q_score is not null
        or nl.q_views is not null
      )
  and (
        nl.asker_name is not null
        or nl.top3_tags is not null
      )
order by
    nl.q_views desc nulls last,
    nl.q_score desc nulls last,
    nl.q_created desc
limit 200;