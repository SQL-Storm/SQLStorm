-- {"query": "11.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2075} 
with
-- recent active questions with tag arrays and normalized owner info
RecentQuestions as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    coalesce(p.OwnerUserId, -1) as OwnerUserId,
    case when p.Tags is null then array[]::varchar[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray,
    regexp_replace(coalesce(p.Body,''), '\s+', ' ', 'g') as BodySnippet,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '1 year'
),

-- top answerers per question with window functions and correlated existence
TopAnswers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    a.CommentCount,
    a.Body,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn,
    count(*) over (partition by a.ParentId) as AnswerCountForQuestion,
    exists (
      select 1 from Votes v2
      where v2.PostId = a.Id and v2.VoteTypeId = 2 and v2.CreationDate >= now() - interval '90 days'
    ) as HasRecentUpvotes
  from Posts a
  where a.PostTypeId = 2
    and a.ParentId in (select Id from RecentQuestions)
),

-- badge summary for users involved in these posts (including owners and answerers)
UserBadges as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    bool_or(b.TagBased) as HasTagBadges,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Badges b on b.UserId = u.Id
  where u.Id in (
    select distinct OwnerUserId from RecentQuestions
    union
    select distinct OwnerUserId from Posts where PostTypeId = 2 and ParentId in (select Id from RecentQuestions)
  )
  group by u.Id, u.DisplayName, u.Reputation
),

-- compute linkage metrics: duplicates and links among the candidate set
LinkGraph as (
  select
    rq.Id as QuestionId,
    lt.Name as LinkType,
    pl.RelatedPostId,
    pl.PostId,
    count(*) over (partition by rq.Id) as OutgoingLinks,
    sum(case when lt.Id = 3 then 1 else 0 end) over (partition by rq.Id) as DuplicateLinks
  from RecentQuestions rq
  left join PostLinks pl on pl.PostId = rq.Id
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
),

-- aggregate comments sentiment-like quick metrics using string expressions and null logic
CommentMetrics as (
  select
    c.PostId,
    count(*) as TotalComments,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
    sum(case when c.Score < 0 then 1 else 0 end) as NegativeComments,
    max(c.CreationDate) as LastCommentAt,
    bool_or(lower(c.Text) like '%thank%' or lower(c.Text) like '%thanks%') as HasThanks,
    bool_or(c.Text is null) as AnyNullText
  from Comments c
  where c.PostId in (select Id from RecentQuestions)
  group by c.PostId
),

-- historical edit activity for recent questions using correlated subquery and JSON aggregation
EditActivity as (
  select
    ph.PostId,
    count(*) as EditCount,
    min(ph.CreationDate) as FirstEdit,
    max(ph.CreationDate) as LastEdit,
    json_agg(distinct ph.PostHistoryTypeId order by ph.PostHistoryTypeId) as HistoryTypesSeen,
    (select ph2.Text from PostHistory ph2 where ph2.PostId = ph.PostId and ph2.PostHistoryTypeId = 2 order by ph2.CreationDate asc limit 1) as InitialBodySample
  from PostHistory ph
  where ph.PostId in (select Id from RecentQuestions)
  group by ph.PostId
),

-- tag popularity across the candidate questions
TagPopularity as (
  select tag, count(*) as Occurrences
  from (
    select unnest(TagArray) as tag from RecentQuestions
  ) t
  group by tag
  order by Occurrences desc
),

-- cross-join trick to generate heavy compute with complicated expression
HeavyCompute as (
  select
    rq.Id,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    coalesce(tb.Occurrences,0) as TopTagOccurrence,
    lb.OutgoingLinks,
    lb.DuplicateLinks,
    coalesce(cm.TotalComments,0) as TotalComments,
    coalesce(ea.EditCount,0) as EditCount,
    (
      -- composite score with various non-linearities, null logic, string length, and windowed rank
      greatest(
        0,
        (rq.Score::numeric * 1.5)
        + ln(greatest(1, rq.ViewCount)) * 0.7
        + (coalesce(tb.Occurrences,0)::numeric ^ 0.9)
        - (coalesce(lb.DuplicateLinks,0)::numeric * 2)
        + (coalesce(cm.PositiveComments,0) * 0.5)
        - (coalesce(cm.NegativeComments,0) * 0.75)
        + (case when ea.EditCount > 5 then 3 else ea.EditCount::numeric * 0.4 end)
        + (length(coalesce(rq.BodySnippet,''))::numeric / 1000)
        - (case when rq.AnswerCount = 0 then 2 else 0 end)
      )
    ) as CompositeScore
  from RecentQuestions rq
  left join (
    select rq2.Id, tp.Occurrences
    from RecentQuestions rq2
    left join lateral (
      select max(Occurrences) as Occurrences
      from (
        select unnest(rq2.TagArray) as t
      ) z
      left join TagPopularity tp on tp.tag = z.t
    ) tp on true
  ) tb on tb.Id = rq.Id
  left join (
    select QuestionId, max(OutgoingLinks) as OutgoingLinks, max(DuplicateLinks) as DuplicateLinks
    from LinkGraph
    group by QuestionId
  ) lb on lb.QuestionId = rq.Id
  left join CommentMetrics cm on cm.PostId = rq.Id
  left join EditActivity ea on ea.PostId = rq.Id
),

-- final ranking with window functions, correlated subquery to fetch top answer content and author badge influence
FinalRanked as (
  select
    hc.*,
    row_number() over (order by hc.CompositeScore desc, hc.Score desc, hc.ViewCount desc) as GlobalRank,
    rank() over (partition by (select coalesce(tb2.Occurrences,0) from (select max(Occurrences) Occurrences from (select unnest(rq.TagArray) t) z left join TagPopularity tp on tp.tag = z.t) tb2 where true) order by hc.CompositeScore desc) as TagGroupRank
  from HeavyCompute hc
  left join RecentQuestions rq on rq.Id = hc.Id
)

select
  fr.GlobalRank,
  fr.Id as QuestionId,
  fr.Title,
  fr.Score as QuestionScore,
  fr.ViewCount,
  fr.CompositeScore,
  fr.TopTagOccurrence,
  fr.OutgoingLinks,
  fr.DuplicateLinks,
  fr.TotalComments,
  fr.EditCount,
  fr.GlobalRank % 10 as BucketModulo10,
  substr(fr.Title,1,120) || case when length(fr.Title) > 120 then '...' else '' end as TitlePreview,
  -- correlated fetch of top answer summary and owner badge weight
  (select json_build_object(
     'AnswerId', ta.AnswerId,
     'Score', ta.Score,
     'IsRecentUpvoted', ta.HasRecentUpvotes,
     'OwnerUserId', ta.OwnerUserId,
     'OwnerReputation', coalesce(ub.Reputation,0),
     'OwnerGold', coalesce(ub.GoldBadges,0)
   )
   from TopAnswers ta
   left join UserBadges ub on ub.UserId = ta.OwnerUserId
   where ta.QuestionId = fr.Id and ta.rn = 1
   limit 1
  ) as TopAnswerSummary,
  -- include edit history sample and comment flags
  (select json_build_object('EditCount', ea.EditCount, 'LastEdit', ea.LastEdit, 'InitialBodySnippet', substr(coalesce(ea.InitialBodySample,''),1,200))
   from EditActivity ea where ea.PostId = fr.Id
  ) as EditSummary,
  (select json_build_object('TotalComments', coalesce(cm.TotalComments,0),'HasThanks', coalesce(cm.HasThanks,false),'AnyNullText', coalesce(cm.AnyNullText,false))
   from CommentMetrics cm where cm.PostId = fr.Id
  ) as CommentSummary
from FinalRanked fr
order by fr.GlobalRank
limit 250;