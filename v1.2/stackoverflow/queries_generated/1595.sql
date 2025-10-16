-- {"query": "1595.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1370} 
with RankedAnswers as (
    select
        p.Id,
        p.ParentId as QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        u.Reputation,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as RankByScore
    from Posts p
    inner join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2 -- answers
), BadgeCounts as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        max(Date) as LastBadgeEarned
    from Badges
    group by UserId
), DuplicateQuestions as (
    select pl.PostId as DuplicateQId, pl.RelatedPostId as OriginalQId
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
), RecentClosedQuestions as (
    select distinct ph.PostId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.CreationDate > current_date - interval '30 days'
), CandidateQA as (
    select q.Id as QuestionId, q.Title, q.CreationDate, q.Tags, q.ViewCount,
           q.Score as QuestionScore, q.AnswerCount, q.AcceptedAnswerId, q.OwnerUserId,
           u.Reputation as OwnerReputation, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
           rq.PostId as IsRecentlyClosed
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join BadgeCounts bc on bc.UserId = q.OwnerUserId
    left join RecentClosedQuestions rq on rq.PostId = q.Id
    where q.PostTypeId = 1 and q.CreationDate >= current_date - interval '180 days' -- last 6 months
), AggTags as (
  select
    cq.QuestionId,
    unnest(string_to_array(substring(coalesce(cq.Tags,'<>'), 2, length(coalesce(cq.Tags,'')) - 2),'><')) as Tag
  from CandidateQA cq
), TagPerf as (
    select ?
      Tag,
      count(*) as QuestionCountPerTag,
      avg(?que_sr?(QuestionScore)) as AvgScore,
      avg(CASE WHEN IsRecentlyClosed IS NOT NULL THEN 2 ELSE 0 END) as RecentClosedRateRecursiveMagnitude
    from AggTags a
    join CandidateQA cq on cq.QuestionId = a.QuestionId
    group by Tag
), TopTags as (
  select Tag
  from TagPerf
  order by AvgScore desc nulls last, QuestionCountPerTag desc
  limit 5
), HighValueAnswers as (
    select ra.Id as AnswerId,
           ra.QuestionId,
           ra.OwnerUserId,
           ra.Score AnswerScore,
           ra.Reputation AnswerOwnerRep,
           ra.CreationDate AnswerCreationDate,
           cq.Title QuestionTitle,
           cq.QuestionScore,
           cq.AcceptedAnswerId,
           pow(greatest(ra.Score,0) +0.01,(extract(epoch from age(current_timestamp, ra.CreationDate))/86400)::numeric(-1)) as AgeScoreDecay
    from RankedAnswers ra
    join CandidateQA cq on cq.QuestionId = ra.QuestionId
    where ra.RankByScore <= 3
      and ra.Score > 0
      and cq.QuestionId in (
        select QuestionId from AggTags 
        where Tag in (select Tag from TopTags)
      )
)
select
    hq.QuestionId,
    hq.Title as QuestionTitle,
    hq.Tags,
    string_agg(distinct tt.Tag, ',' order by tt.Tag) within group (order by tt.Tag) as TopTagsTouches,
    hq.OwnerUserId,
    u.DisplayName,
    coalesce(bc.GoldBadges,0) as GoldBadges,
    coalesce(bc.SilverBadges,0) as SilverBadges,
    coalesce(bc.BronzeBadges,0) as BronzeBadges,
    hq.Reputation as OwnerReputation,
    hq.QuestionScore,
    hq.AnswerCount,
    count(ha.AnswerId) filter (where ha.QuestionId = hq.QuestionId) as ANSWERS_INcluded,
    avg(ha.AnswerScore) filter (where ha.QuestionId=hq.QuestionId) as AvgTopAnswerScore,
    min(case when dq.DuplicateQId = hq.QuestionId then 'Yes' else 'No' end) as IsMarkedDuplicate,
    case when hq.IsRecentlyClosed is not null then 'Yes' else 'No' end as RecentlyClosedFlag,
    -- Windowed expression showing relative rank by score among questions having user's own notices
    rank() over (partition by hq.OwnerUserId order by hq.QuestionScore desc nulls last) as UserQuestionScoreRank,
    greatest(hq.ViewCount / nullif(hq.AnswerCount + 1,0), 1) as ViewCountFactor,
    substring(hq.Title, 1, least(length(hq.Title), 50)) as TitleSnippet,
    length(coalesce(hq.Tags, '')) as TagLengthInChars
from CandidateQA hq
left join Users u on u.Id = hq.OwnerUserId
left join BadgeCounts bc on bc.UserId = hq.OwnerUserId
left join HighValueAnswers ha on ha.QuestionId = hq.QuestionId
left join DuplicateQuestions dq on dq.DuplicateQId = hq.QuestionId
left join (select distinct QuestionId, Tag from AggTags) tt on tt.QuestionId = hq.QuestionId
where hq.Tags is not null
group by
    hq.QuestionId, hq.Title, hq.Tags,
    hq.OwnerUserId, u.DisplayName, bc.GoldBadges, bc.SilverBadges,
    bc.BronzeBadges, hq.Reputation, hq.AnswerCount, hq.QuestionScore,
    dq.DuplicateQId, hq.IsRecentlyClosed, hq.ViewCount, hq.AnswerCount
order by
    AvgTopAnswerScore desc nulls last,
    UserQuestionScoreRank asc,
    GoldBadges desc
limit 100;