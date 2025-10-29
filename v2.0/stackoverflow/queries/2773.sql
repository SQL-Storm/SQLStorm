-- {"query": "2773.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1577}
with ranked_answers as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.Reputation as AnswererReputation,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    join PostTypes pt on a.PostTypeId = pt.Id and pt.Name = 'Answer'
    left join Users u on a.OwnerUserId = u.Id
), question_stats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        coalesce(q.AcceptedAnswerId, 0) as AcceptedAnswerId,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentsCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes,
        (select string_agg(distinct b.Name, ',' order by b.Name) 
            from Badges b where b.UserId = u.Id and b.Class = 1) as OwnerGoldBadges
    from Posts q
    join PostTypes pt on q.PostTypeId = pt.Id and pt.Name = 'Question'
    left join Users u on q.OwnerUserId = u.Id
), accepted_answer_info as (
    select 
        a.Id as AnswerId,
        a.CreationDate,
        a.Score,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentsCount,
        (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
), badge_counts as (
    select UserId, 
       count(case when Class = 1 then 1 end) as GoldBadges,
       count(case when Class = 2 then 1 end) as SilverBadges,
       count(case when Class = 3 then 1 end) as BronzeBadges
    from Badges
    group by UserId
), dup_links as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
), latest_post_history as (
    select ph.PostId, max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    group by ph.PostId
), questions_with_flags as (
    select q.QuestionId,
           q.Title, q.QuestionCreationDate as QuestionDate,
           q.ViewCount,
           q.OwnerUserId,
           q.OwnerReputation,
           coalesce(rn.AnswerId, 0) as TopAnswerId,
           rn.AnswerScore,
           rn.AnswerCreationDate,
           rn.AnswererReputation,
           q.AcceptedAnswerId,
           a.Score as AcceptedAnswerScore,
           a.OwnerUserId as AcceptedAnswerOwnerUserId,
           a.DisplayName as AcceptedAnswerOwnerDisplayName,
           a.Reputation as AcceptedAnswerOwnerReputation,
           q.QuestionCommentsCount,
           q.QuestionUpVotes,
           b.GoldBadges as OwnerGoldBadgesCount,
           b.SilverBadges as OwnerSilverBadgesCount,
           b.BronzeBadges as OwnerBronzeBadgesCount,
           dup.RelatedPostId as DuplicateOfQuestionId,
           ph.LastEditDate,
           q.QuestionScore
    from question_stats q
    left join ranked_answers rn on q.QuestionId = rn.QuestionId and rn.rn = 1
    left join accepted_answer_info a on q.AcceptedAnswerId = a.AnswerId
    left join badge_counts b on q.OwnerUserId = b.UserId
    left join dup_links dup on dup.PostId = q.QuestionId
    left join latest_post_history ph on ph.PostId = q.QuestionId
    where q.ViewCount > 1000
    and (q.QuestionScore > 5 or q.QuestionUpVotes > 10)
    and (rn.AnswerScore is null or rn.AnswerScore > 0)
)
select 
    qwf.QuestionId,
    qwf.Title,
    qwf.QuestionDate,
    qwf.ViewCount,
    coalesce(qwf.OwnerUserId, -1) as OwnerUserId,
    coalesce(qwf.OwnerReputation, 0) as OwnerReputation,
    concat(coalesce(u.DisplayName, 'unknown'), ' (', coalesce(cast(u.Reputation as varchar), '0'), ' rep)') as OwnerDisplay,
    qwf.TopAnswerId,
    qwf.AnswerScore,
    qwf.AnswerCreationDate,
    qwf.AnswererReputation,
    qwf.AcceptedAnswerId,
    qwf.AcceptedAnswerScore,
    concat(coalesce(qwf.AcceptedAnswerOwnerDisplayName, 'noone'), ' (', coalesce(cast(qwf.AcceptedAnswerOwnerReputation as varchar), '0'), ' rep)') as AcceptedAnswerOwner,
    qwf.QuestionCommentsCount,
    qwf.QuestionUpVotes,
    qwf.OwnerGoldBadgesCount,
    qwf.OwnerSilverBadgesCount,
    qwf.OwnerBronzeBadgesCount,
    case when qwf.DuplicateOfQuestionId is not null then 'Yes' else 'No' end as IsDuplicate,
    qwf.LastEditDate,
    rank() over (partition by (case when qwf.OwnerReputation >= 10000 then 1 else 0 end) order by qwf.ViewCount desc) as PopularityRankByReputationTier,
    split_part(regexp_replace(qwf.Title, '[^a-zA-Z0-9 ]', '', 'g'), ' ', 1) as CleanFirstWordInTitle,
    case 
        when qwf.AcceptedAnswerId = 0 and qwf.AnswerScore > 10 and qwf.QuestionScore > 20 then 'HighScoreUnacceptedHighAnswer'
        else 'Other'
    end as QuestionTypeFlag
from questions_with_flags qwf
left join Users u on u.Id = qwf.OwnerUserId
where (qwf.LastEditDate is null or qwf.LastEditDate < (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'))
union
select 
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionDate,
    q.ViewCount,
    q.OwnerUserId,
    u.Reputation as OwnerReputation,
    u.DisplayName as OwnerDisplay,
    null as TopAnswerId,
    null as AnswerScore,
    null as AnswerCreationDate,
    null as AnswererReputation,
    null as AcceptedAnswerId,
    null as AcceptedAnswerScore,
    null as AcceptedAnswerOwner,
    null as QuestionCommentsCount,
    null as QuestionUpVotes,
    null as OwnerGoldBadgesCount,
    null as OwnerSilverBadgesCount,
    null as OwnerBronzeBadgesCount,
    null as IsDuplicate,
    null as LastEditDate,
    null as PopularityRankByReputationTier,
    null as CleanFirstWordInTitle,
    'OrphanQuestions' as QuestionTypeFlag
from Posts q
left join Users u on q.OwnerUserId = u.Id
where q.PostTypeId = 1 and q.AcceptedAnswerId is null and not exists (
    select 1 from Posts a where a.ParentId = q.Id
)
order by PopularityRankByReputationTier nulls last, ViewCount desc, QuestionDate desc
limit 100;