-- {"query": "2943.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1685} 
with RecursiveTagAgg as (
    select
        p.Id as PostId,
        p.Tags,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
UserBadgesCount as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostScoreStats as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgUserScore,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank,
        dense_rank() over (order by p.Score desc) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1,2) -- Questions and Answers
),
LatestPostHistory as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,12,13)
    order by ph.PostId, ph.CreationDate desc
),
PostLinksWithTypes as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
),
QuestionAnswerAggregate as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        count(a.Id) as AnswerCount,
        coalesce(sum(a.Score),0) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        max(p.CreationDate) as LastPostDate,
        lag(max(p.CreationDate)) over (order by u.Id) as PrevUserLastPostDate,
        datediff('day', lag(max(p.CreationDate)) over (order by u.Id), max(p.CreationDate)) as DaysBetweenLastPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionsWithDuplicateLinks as (
    select distinct
        q.Id as QuestionId,
        q.Title,
        plwr.RelatedPostId as DuplicateOfQuestionId
    from Posts q
    join PostLinksWithTypes plwr on plwr.PostId = q.Id and plwr.LinkTypeName = 'Duplicate'
    where q.PostTypeId = 1
),
AnswerWithAcceptedFlag as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        case when q.AcceptedAnswerId = a.Id then true else false end as IsAccepted,
        a.Score as AnswerScore,
        a.OwnerUserId
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
),
FinalFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerDisplayName,
        coalesce(ub.GoldBadges, 0) as OwnerGoldBadges,
        coalesce(ub.SilverBadges,0) as OwnerSilverBadges,
        coalesce(ub.BronzeBadges,0) as OwnerBronzeBadges,
        qaa.AnswerCount,
        qaa.TotalAnswerScore,
        qaa.MaxAnswerScore,
        qaa.MinAnswerScore,
        lph.PostHistoryTypeId as LatestPostHistoryType,
        cr.CloseReasonName,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(distinct ph2.UserId) from PostHistory ph2 where ph2.PostId = p.Id and ph2.UserId is not null) as DistinctEditorCount,
        rank() over (partition by u.Id order by p.Score desc) as OwnerPostScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgesCount ub on ub.UserId = u.Id
    left join QuestionAnswerAggregate qaa on qaa.QuestionId = p.Id and p.PostTypeId = 1
    left join LatestPostHistory lph on lph.PostId = p.Id
    left join ClosedQuestionsWithReason cr on cr.PostId = p.Id
    where p.PostTypeId in (1,2)
)
select
    f.Id as PostId,
    f.Title,
    f.CreationDate,
    f.Score,
    f.ViewCount,
    coalesce(f.Tags, '') as Tags,
    f.OwnerDisplayName,
    f.OwnerGoldBadges,
    f.OwnerSilverBadges,
    f.OwnerBronzeBadges,
    f.AnswerCount,
    f.TotalAnswerScore,
    f.MaxAnswerScore,
    f.MinAnswerScore,
    f.LatestPostHistoryType,
    f.CloseReasonName,
    f.CommentCount,
    f.DistinctEditorCount,
    f.OwnerPostScoreRank,
    array_agg(distinct rt.Tag) filter (where rt.PostId = f.Id) as ParsedTags,
    ua.DaysBetweenLastPosts,
    coalesce(dq.DuplicateOfQuestionId, -1) as DuplicateOfQuestionId,
    sum(case when aaf.IsAccepted then 1 else 0 end) over (partition by f.OwnerDisplayName) as TotalAcceptedAnswersByOwner,
    case
        when f.Score > 100 then 'High Score'
        when f.Score between 50 and 100 then 'Medium Score'
        else 'Low Score'
    end as ScoreCategory,
    concat_ws(' | ', f.OwnerDisplayName, 'Post:', f.Id::text, 'Score:', f.Score::text) as CompositeInfo,
    case when f.CloseReasonName is not null then true else false end as IsClosed
from FinalFilteredPosts f
left join RecursiveTagAgg rt on rt.PostId = f.Id
left join UserActivityWindow ua on ua.UserId = f.OwnerUserId
left join QuestionsWithDuplicateLinks dq on dq.QuestionId = f.Id
left join AnswerWithAcceptedFlag aaf on aaf.QuestionId = f.Id
where (f.Score > 10 or f.ViewCount > 1000) and f.OwnerPostScoreRank <= 5
order by f.Score desc, f.CreationDate asc
limit 100;