-- {"query": "1296.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1566} 
with RankedAnswers as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.CreationDate,
        a.Score,
        u.DisplayName as AnswererName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2 -- Answers
),
QuestionsCTE as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        u.DisplayName as QuestionOwner,
        b.BadgesCount,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        ph.LastEditDate,
        coalesce(closeReason.Name, 'Not Closed') as CloseReason,
        Rank() over (order by q.Score desc, q.ViewCount desc) as PopularityRank
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join (
        select
            UserId,
            count(*) as BadgesCount,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) b on b.UserId = q.OwnerUserId
    left join (
        select
            PostId,
            max(LastEditDate) as LastEditDate
        from Posts
        group by PostId
    ) ph on ph.PostId = q.Id
    left join PostHistory phc on phc.PostId = q.Id and phc.PostHistoryTypeId = 10 -- Post Closed
    left join CloseReasonTypes closeReason on closeReason.Id = try_cast(phc.Comment as smallint)
    where q.PostTypeId = 1
),
AnswerAggregates as (
    select
        QuestionId,
        count(*) as TotalAnswers,
        sum(case when Score > 10 then 1 else 0 end) as HighlyRatedAnswers,
        max(Score) as MaxAnswerScore,
        count(distinct AnswererName) as UniqueAnswerers
    from RankedAnswers
    group by QuestionId
),
CommentAggregates as (
    select
        p.Id as PostId,
        count(c.Id) filter (where c.Score > 5) as TopCommentsCount,
        count(c.Id) as TotalComments,
        string_agg(distinct coalesce(c.UserDisplayName, 'Unknown'), ', ' order by c.CreationDate desc) as CommentersSample
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
Duplicates as (
    select
        pl.PostId,
        count(pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select
    q.QuestionId,
    q.Title,
    -- Fancy tag count calculated by splitting string '<tag1><tag2>' and counting
    cardinality(regexp_split_to_array(trim(both '<' from q.Tags), '><')) as TagCount,
    q.QuestionOwner,
    coalesce(q.BadgesCount, 0) as OwnerBadgeCount,
    q.GoldBadges,
    q.SilverBadges,
    q.BronzeBadges,
    q.QuestionScore,
    q.ViewCount,
    coalesce(a.TotalAnswers, 0) as TotalAnswers,
    coalesce(a.HighlyRatedAnswers, 0) as HighlyRatedAnswers,
    coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(a.UniqueAnswerers, 0) as UniqueAnswerers,
    c.TopCommentsCount,
    c.TotalComments,
    substring(c.CommentersSample from 1 for 100) as CommentersSample,
    coalesce(d.DuplicateCount, 0) as DuplicateCount,
    q.CloseReason,
    q.LastEditDate,
    q.PopularityRank,
    -- Window function: percentage rank by score among all questions
    round(percent_rank() over (order by q.QuestionScore desc) * 100, 2) as ScorePercentRank,
    -- Complex condition: question "fresh" if created in last year, score above median and not closed
    case 
        when q.CreationDate > current_date - interval '365 days'
          and q.QuestionScore > (select percentile_cont(0.5) within group (order by Score) from Posts where PostTypeId=1)
          and q.CloseReason = 'Not Closed'
        then 'FreshPopularOpen'
        else 'Other'
    end as StatusCategory,
    -- Correlated subquery calculating average score of answers per question
    (select avg(coalesce(Score, 0)) from Posts ans where ans.ParentId = q.QuestionId and ans.PostTypeId = 2) as AvgAnswerScore,
    -- String manipulation and NULL logic combining owner name and tags
    coalesce(q.QuestionOwner, 'anonymous') || ' | Tags: ' || coalesce(q.Tags, 'none') as OwnerAndTags
from QuestionsCTE q
left join AnswerAggregates a on a.QuestionId = q.QuestionId
left join CommentAggregates c on c.PostId = q.QuestionId
left join Duplicates d on d.PostId = q.QuestionId
where 
    (a.HighlyRatedAnswers > 0 or c.TopCommentsCount > 2)
    and q.ViewCount > 1000
union
select
    fav.Id as QuestionId,
    fav.Title,
    cardinality(regexp_split_to_array(trim(both '<' from fav.Tags), '><')) as TagCount,
    u.DisplayName as QuestionOwner,
    count(b.Id) as OwnerBadgeCount,
    sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges,
    fav.Score,
    fav.ViewCount,
    0 as TotalAnswers,
    0 as HighlyRatedAnswers,
    0 as MaxAnswerScore,
    0 as UniqueAnswerers,
    0 as TopCommentsCount,
    0 as TotalComments,
    null as CommentersSample,
    0 as DuplicateCount,
    'Not Closed' as CloseReason,
    fav.LastEditDate,
    100000 as PopularityRank,
    0 as ScorePercentRank,
    'FavoritedQuestion' as StatusCategory,
    null as AvgAnswerScore,
    coalesce(u.DisplayName, 'anonymous') || ' | Tags: ' || coalesce(fav.Tags, 'none') as OwnerAndTags
from Posts fav
left join Users u on fav.OwnerUserId = u.Id
left join Badges b on b.UserId = u.Id
where fav.PostTypeId = 1
  and fav.FavoriteCount > 10
order by PopularityRank asc, TotalAnswers desc, q.QuestionScore desc
limit 100;