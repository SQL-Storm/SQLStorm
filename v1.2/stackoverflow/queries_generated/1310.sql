-- {"query": "1310.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1822} 
with RecursiveUserRanks as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as RankDescRep,
        rank() over (partition by date_trunc('year', u.CreationDate) order by u.Reputation desc) as YearlyRank,
        dense_rank() over (order by substring(u.Location from '\\w+')) as LocationRank
    from Users u
    where u.Reputation is not null
),
FilteredPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(p.ViewCount, 0) as ViewCount,
        p.AcceptedAnswerId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate
    from Posts p
    where p.PostTypeId in (1,2) -- question or answer
      and p.CreationDate between '2019-01-01' and '2024-01-01'
),
AnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Reputation as AnswererReputation,
        u.DisplayName as AnswererName,
        ua.BadgesCount as AnswererBadgeCount
    from FilteredPosts a
    left join Users u on a.OwnerUserId = u.Id
    left join (
        select UserId, count(*) BadgeCnt from Badges group by UserId
    ) ua on a.OwnerUserId = ua.UserId
    where a.PostTypeId = 2
),
MaxAnswerScores as (
    select 
        QuestionId,
        max(AnswerScore) as MaxAnswerScore
    from AnswerDetails
    group by QuestionId
),
QuestionStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreationDate,
        -- Number of answers QUESTION received
        q.AnswerCount,
        -- accepted answer id may be null
        q.AcceptedAnswerId,
        fu.RankDescRep,
        fu.YearlyRank, 
        fu.LocationRank,
        fc.DateClosed,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        count(distinct po.Id) as PostLinksCount,
        coalesce(array_agg(distinct lnk.Name) filter (where lnk.Name is not null), '{}') as LinkTypesNames,
        -- tags as split array removing <> chars; pattern accounts for tags format <tag1><tag2> 
        string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><') as TagsArray
    from FilteredPosts q
    left join RecursiveUserRanks fu on q.OwnerUserId = fu.Id
    left join PostHistory ph on ph.PostId = q.Id 
        and ph.PostHistoryTypeId = 10 
        and ph.CreationDate >= q.CreationDate
    left join PostLinks po on po.PostId = q.Id
    left join LinkTypes lnk on lnk.Id = po.LinkTypeId
    left join (
       select PostId, min(CreationDate) as DateClosed from PostHistory
       where PostHistoryTypeId = 10 group by PostId
    ) fc on fc.PostId = q.Id
    group by q.Id, q.Title, q.Score, q.CreationDate, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId, fu.RankDescRep, fu.YearlyRank, fu.LocationRank, fc.DateClosed
),
AnswerWithRanks as (
    select
        ad.*,
        ROW_NUMBER() OVER (PARTITION BY ad.QuestionId ORDER BY ad.AnswerScore DESC, ad.AnswerCreationDate ASC) as AnswerRankByScore,
        -- boolean indicating if answer is accepted answer
        CASE WHEN ad.AnswerId = qs.AcceptedAnswerId THEN 1 ELSE 0 END as IsAccepted,
        qs.QuestionScore,
        qs.QuestionViews,
        qs.MonthRank
    from AnswerDetails ad
    join QuestionStats qs on qs.QuestionId = ad.QuestionId
),
TopTags200 as (
    select distinct unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><')) as Tag
    from Posts
    where PostTypeId = 1
    group by Tag order by sum(ViewCount) desc
    limit 200
),
FinalAggregated as (
    select 
        q.QuestionId,
        q.Title,
        q.QuestionScore,
        q.QuestionViews,
        array_to_string(q.TagsArray, ',') as TagsListing,
        count(distinct a.AnswerId) as TotalAnswers,
        sum(a.IsAccepted::int) as TotalAcceptedAnswers,
        max(a.AnswerScore) as HighestAnswerScore,
        avg(a.AnswerScore) as AvgAnswerScore,
        avg(u.Reputation) filter (where u.Id is not null) as AvgAnswererReputation,
        count(distinct b.Id) as BadgeCountGold,
        string_agg(distinct lt.Name, ';') as LinkTypes,
        q.CloseVotesCount,
        extract(year from q.QuestionCreationDate) as CreationYear,
        case 
          when q.ClosedDate is not null then 'Closed' 
          else 'Open' 
        end as PostStatus,
        dense_rank() over (order by q.QuestionScore desc) as QuestionRankByScore
    from QuestionStats q
    left join AnswerDetails a on a.QuestionId = q.QuestionId
    left join Users u on u.Id = a.AnswererName -- joining by Id here possibly add joins chained on Answerer? Correct is by Answerer? Fix join conditions to relation answerer for reputation
        on a.AnswererName = u.DisplayName
    left join Badges b on b.UserId = u.Id and b.Class = 1 -- gold badges
    left join PostLinks pl on pl.PostId = q.QuestionId
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by q.QuestionId, q.Title, q.QuestionScore, q.QuestionViews, q.TagsArray, q.CloseVotesCount, q.QuestionCreationDate, q.ClosedDate
),
TagFiltered as(
    select 
        fa.*
    from FinalAggregated fa
    where exists (
        select 1 
        from unnest(string_to_array(fa.TagsListing, ',')) t(tag) 
        join TopTags200 tg on tg.Tag = t.tag
    )
    and fa.QuestionRankByScore <= 1000
)
select
    tf.QuestionId,
    tf.Title,
    left(tf.Title, 30) || '...' as TitlePreview,
    tf.QuestionScore,
    tf.QuestionViews,
    tf.TotalAnswers,
    tf.TotalAcceptedAnswers,
    tf.HighestAnswerScore,
    round(tf.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    coalesce(round(tf.AvgAnswererReputation,0),0) as AvgAnswererReputation,
    tf.BadgeCountGold,
    tf.LinkTypes,
    tf.CloseVotesCount,
    tf.CreationYear,
    tf.PostStatus,
    tf.QuestionRankByScore,
    case 
      when tf.TotalAcceptedAnswers = 0 then 'No Accepted Answer'
      when tf.HighestAnswerScore > 10 then 'High Scoring Answer Present'
      else 'Standard'
    end as AnswerQuality,
    translate(tf.TagsListing, ',', '|') as TagPipes,
    string_agg(distinct left(lkp.Name,5), ',' order by lkp.Name desc) filter (where lkp.Name is not null) as ShortLinkTypeNames
from TagFiltered tf
left join PostLinks plk on plk.PostId = tf.QuestionId
left join LinkTypes lkp on lkp.Id = plk.LinkTypeId
group by tf.QuestionId, tf.Title, tf.QuestionScore, tf.QuestionViews, tf.TotalAnswers, tf.TotalAcceptedAnswers, tf.HighestAnswerScore, tf.AvgAnswerScore, tf.AvgAnswererReputation, tf.BadgeCountGold, tf.LinkTypes, tf.CloseVotesCount, tf.CreationYear, tf.PostStatus, tf.QuestionRankByScore, tf.TagsListing
order by tf.QuestionRankByScore asc
limit 500;