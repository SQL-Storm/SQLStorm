-- {"query": "3.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3790} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
        row_number() over (order by u.creationdate desc, u.id) as rn_newest
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
user_post_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score, 0)) as total_post_score,
        sum(coalesce(p.viewcount, 0)) filter (where p.posttypeid = 1) as total_question_views,
        max(p.lastactivitydate) as last_activity,
        avg(nullif(p.commentcount, 0)) as avg_commentcount_nonzero
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answer_stats as (
    select
        q.owneruserid as asker_id,
        count(a.id) as accepted_answers_received,
        sum(a.score) as accepted_answers_score,
        avg(a.score::numeric) as accepted_answers_avg_score
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
    group by q.owneruserid
),
answerer_accept_rate as (
    select
        a.owneruserid as user_id,
        count(*) as answers_posted,
        count(*) filter (where exists (
            select 1
            from posts q
            where q.posttypeid = 1
              and q.acceptedanswerid = a.id
        )) as answers_accepted
    from posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_expertise as (
    select
        p.owneruserid as user_id,
        lower(trim(split_part(t.tagname, ' ', 1))) as top_tag,
        sum(p.score) as score_in_tag,
        count(*) as posts_in_tag,
        row_number() over (partition by p.owneruserid order by sum(p.score) desc nulls last, count(*) desc, min(p.creationdate)) as tag_rank
    from posts p
    join lateral (
        select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    ) t on p.posttypeid = 1 and p.tags is not null and p.tags like '<%>'
    group by p.owneruserid, top_tag
),
edits_activity as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as total_edits,
        count(*) filter (where ph.posthistorytypeid = 24) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_state_changes,
        max(ph.creationdate) as last_edit_date
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
vote_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as total_bounty_amount,
        min(v.creationdate) as first_vote_date,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
duplicates_matrix as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
question_close_reasons as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_text
    from posthistory ph
    group by ph.postid
),
quality_flags as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        (coalesce(p.score,0) >= 5 and coalesce(p.viewcount,0) >= 1000) as is_popular,
        (p.commentcount is not null and p.commentcount >= 10) as highly_commented,
        (p.closeddate is not null) as was_closed,
        (exists (select 1 from duplicates_matrix d where d.postid = p.id and d.is_duplicate = 1)) as has_duplicate_flag
    from posts p
    where p.owneruserid is not null
),
user_quality_rollup as (
    select
        q.user_id,
        count(*) filter (where q.is_popular) as popular_posts,
        count(*) filter (where q.highly_commented) as highly_commented_posts,
        count(*) filter (where q.was_closed) as closed_posts,
        count(*) filter (where q.has_duplicate_flag) as duplicate_linked_posts
    from quality_flags q
    group by q.user_id
),
recent_hot_questions as (
    select
        ph.postid,
        max(ph.creationdate) as last_hot_date
    from posthistory ph
    where ph.posthistorytypeid = 52
    group by ph.postid
),
user_hotness as (
    select
        p.owneruserid as user_id,
        count(distinct rhq.postid) as hot_questions_count,
        max(rhq.last_hot_date) as last_hot_question_date
    from recent_hot_questions rhq
    join posts p on p.id = rhq.postid and p.posttypeid = 1
    group by p.owneruserid
),
stringy as (
    select
        u.id as user_id,
        lower(regexp_replace(coalesce(u.displayname, 'anon'), '[^a-z0-9]+', '_', 'g')) || '_' || lpad(u.id::text, 6, '0') as handle_key,
        case
            when u.location ilike '%remote%' or u.location ilike '%anywhere%' then 'Remote'
            when u.location ilike '%usa%' or u.location ilike '%united states%' then 'USA'
            when u.location ilike '%india%' then 'India'
            when u.location is null then 'Unknown'
            else 'Other'
        end as region_bucket
    from users u
),
activity_windows as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month_bucket,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as month_score,
        dense_rank() over (partition by p.owneruserid order by date_trunc('month', p.creationdate)) as month_seq
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_trends as (
    select
        aw.user_id,
        aw.month_bucket,
        aw.q_count,
        aw.a_count,
        aw.month_score,
        sum(aw.q_count) over (partition by aw.user_id order by aw.month_bucket rows between unbounded preceding and current row) as cum_q,
        sum(aw.a_count) over (partition by aw.user_id order by aw.month_bucket rows between unbounded preceding and current row) as cum_a,
        avg(aw.month_score) over (partition by aw.user_id order by aw.month_bucket rows between 2 preceding and current row) as rolling3_score_avg
    from activity_windows aw
),
power_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.net_votes,
        coalesce(upa.questions,0) as questions,
        coalesce(upa.answers,0) as answers,
        coalesce(upa.total_post_score,0) as total_post_score,
        coalesce(upa.total_question_views,0) as total_question_views,
        upa.last_activity,
        coalesce(upa.avg_commentcount_nonzero, 0) as avg_commentcount_nonzero,
        coalesce(aas.accepted_answers_received,0) as accepted_answers_received,
        coalesce(aas.accepted_answers_score,0) as accepted_answers_score,
        coalesce(aas.accepted_answers_avg_score,0) as accepted_answers_avg_score,
        coalesce(aar.answers_posted,0) as answers_posted,
        coalesce(aar.answers_accepted,0) as answers_accepted,
        case when coalesce(aar.answers_posted,0) = 0 then null
             else round(100.0 * coalesce(aar.answers_accepted,0) / nullif(aar.answers_posted,0), 2)
        end as answer_accept_rate_pct,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        ub.last_badge_date,
        coalesce(ea.total_edits,0) as total_edits,
        coalesce(ea.suggested_edits_applied,0) as suggested_edits_applied,
        coalesce(ea.mod_state_changes,0) as mod_state_changes,
        ea.last_edit_date,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.total_bounty_amount,0) as total_bounty_amount,
        va.first_vote_date,
        va.last_vote_date,
        coalesce(uqr.popular_posts,0) as popular_posts,
        coalesce(uqr.highly_commented_posts,0) as highly_commented_posts,
        coalesce(uqr.closed_posts,0) as closed_posts,
        coalesce(uqr.duplicate_linked_posts,0) as duplicate_linked_posts,
        coalesce(uh.hot_questions_count,0) as hot_questions_count,
        uh.last_hot_question_date,
        s.handle_key,
        s.region_bucket
    from recent_users ru
    left join user_post_activity upa on upa.user_id = ru.user_id
    left join accepted_answer_stats aas on aas.asker_id = ru.user_id
    left join answerer_accept_rate aar on aar.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join edits_activity ea on ea.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join user_quality_rollup uqr on uqr.user_id = ru.user_id
    left join user_hotness uh on uh.user_id = ru.user_id
    left join stringy s on s.user_id = ru.user_id
),
ranked as (
    select
        pu.*,
        row_number() over (
            order by
                coalesce(pu.reputation,0) desc,
                coalesce(pu.total_post_score,0) desc,
                coalesce(pu.hot_questions_count,0) desc,
                pu.user_id
        ) as global_rank,
        dense_rank() over (partition by pu.region_bucket order by coalesce(pu.reputation,0) desc, pu.user_id) as regional_rank,
        ntile(10) over (order by coalesce(pu.reputation,0) desc) as reputation_decile
    from power_users pu
),
activity_delta as (
    select
        at1.user_id,
        at1.month_bucket as month_recent,
        at1.rolling3_score_avg as recent_avg3,
        at0.month_bucket as month_prior,
        at0.rolling3_score_avg as prior_avg3,
        (at1.rolling3_score_avg - at0.rolling3_score_avg) as delta_avg3
    from activity_trends at1
    join activity_trends at0
      on at1.user_id = at0.user_id
     and at1.month_seq = at0.month_seq + 1
    where at1.month_bucket >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts)
),
user_flags as (
    select
        r.user_id,
        (r.reputation >= 10000 and coalesce(r.gold_badges,0) >= 1) as is_high_rep_gold,
        (coalesce(r.answer_accept_rate_pct,0) >= 60) as is_helpful_answerer,
        (coalesce(r.total_edits,0) >= 50 or coalesce(r.suggested_edits_applied,0) >= 25) as is_editor,
        (coalesce(r.popular_posts,0) >= 3 or coalesce(r.hot_questions_count,0) >= 1) as is_influential,
        exists (
            select 1
            from posts p
            where p.owneruserid = r.user_id
              and p.posttypeid = 1
              and p.closeddate is not null
              and p.creationdate >= now() - interval '1 year'
        ) as had_closed_question_recently
    from ranked r
),
final_scores as (
    select
        r.*,
        coalesce(ad.delta_avg3, 0) as recent_score_delta,
        (coalesce(r.total_post_score,0) * 0.4
         + coalesce(r.reputation,0) * 0.3
         + coalesce(r.upvotes_cast,0) * 0.05
         - coalesce(r.downvotes_cast,0) * 0.05
         + coalesce(r.gold_badges,0) * 10
         + coalesce(r.silver_badges,0) * 2
         + coalesce(r.bronze_badges,0) * 0.5
         + least(coalesce(r.hot_questions_count,0), 5) * 3
         + case when uf.is_helpful_answerer then 15 else 0 end
         + case when uf.is_editor then 8 else 0 end
         + case when uf.is_influential then 12 else 0 end
         - case when uf.had_closed_question_recently then 5 else 0 end
         + greatest(coalesce(ad.delta_avg3,0), 0) * 1.5
        ) as composite_score
    from ranked r
    left join activity_delta ad on ad.user_id = r.user_id
    left join user_flags uf on uf.user_id = r.user_id
)
select
    fs.user_id,
    fs.displayname,
    fs.handle_key,
    fs.region_bucket,
    fs.global_rank,
    fs.regional_rank,
    fs.reputation_decile,
    fs.reputation,
    fs.questions,
    fs.answers,
    fs.answers_posted,
    fs.answers_accepted,
    fs.answer_accept_rate_pct,
    fs.total_post_score,
    fs.total_question_views,
    fs.popular_posts,
    fs.highly_commented_posts,
    fs.closed_posts,
    fs.duplicate_linked_posts,
    fs.total_badges,
    fs.gold_badges,
    fs.silver_badges,
    fs.bronze_badges,
    fs.upvotes_cast,
    fs.downvotes_cast,
    fs.total_bounty_amount,
    fs.hot_questions_count,
    fs.last_hot_question_date,
    fs.last_activity,
    fs.last_edit_date,
    fs.first_vote_date,
    fs.last_vote_date,
    fs.creationdate as user_creationdate,
    coalesce(te.top_tag, 'none') as top_tag,
    coalesce(te.score_in_tag, 0) as top_tag_score,
    coalesce(te.posts_in_tag, 0) as top_tag_posts,
    fs.composite_score,
    fs.recent_score_delta
from final_scores fs
left join tag_expertise te on te.user_id = fs.user_id and te.tag_rank = 1
where
    (fs.reputation >= 1000 or fs.total_post_score >= 100)
    and not (fs.displayname is null and fs.questions = 0 and fs.answers = 0)
    and (fs.region_bucket is distinct from 'Unknown' or fs.reputation > 5000)
order by fs.composite_score desc nulls last, fs.global_rank
limit 250;