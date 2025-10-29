-- {"query": "2032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1363} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserScores as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(vp.ScoreVotes), 0) as TotalPostScore
    from Users u
    left join Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(p.Score) as ScoreVotes
        from Posts p
        where p.OwnerUserId is not null and p.OwnerUserId != -1
        group by p.OwnerUserId
    ) vp on vp.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        coalesce(c.CommentCount, 0) as CommentCount
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    where p.PostTypeId = 1 -- questions only
),
QuestionComplex as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        -- count answers for each question via correlated subquery
        (select coalesce(count(1),0) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as AnswerCount,
        -- latest editor's display name or OwnerDisplayName if null
        coalesce(u.DisplayName, p.OwnerDisplayName) as EditorName,
        -- calculate a complex score with weighted components and null logic
        (p.Score * 3 + p.ViewCount / nullif(p.Score + 1, 0) + p.CommentCount * 5 +
            (select coalesce(max(v.CreationDate), '1900-01-01') from Votes v where v.PostId = p.Id and v.VoteTypeId = 2)
        ) as ComplexRank
    from PostWithComments p
    left join Users u on u.Id = p.LastEditorUserId
),
RankedQuestions as (
    select
        q.*,
        row_number() over (partition by substring(q.Tags from '%#"%#"%' for 1) order by q.ComplexRank desc) as TagRank,
        dense_rank() over (order by q.ComplexRank desc) as GlobalRank
    from QuestionComplex q
),
DuplicatesAndLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate', 'Linked')
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as RunningQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as RunningAnswers,
        max(p.CreationDate) over (partition by u.Id) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
FinalAggregated as (
    select
        rs.Id as QuestionId,
        rs.Title,
        rs.Tags,
        rs.CreationDate,
        rs.Score,
        rs.ViewCount,
        rs.CommentCount,
        rs.AnswerCount,
        rs.EditorName,
        rs.ComplexRank,
        rs.TagRank,
        rs.GlobalRank,
        uc.DisplayName as OwnerDisplayName,
        uc.RunningQuestions,
        uc.RunningAnswers,
        da.LinkTypeName,
        da.RelatedPostTitle
    from RankedQuestions rs
    left join UserActivityWindow uc on uc.Id = rs.OwnerUserId
    left join DuplicatesAndLinks da on da.PostId = rs.Id
    where rs.GlobalRank <= 100
)
select
    QuestionId,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    CommentCount,
    AnswerCount,
    EditorName,
    round(ComplexRank, 2) as ComplexRank,
    TagRank,
    GlobalRank,
    OwnerDisplayName,
    coalesce(RunningQuestions, 0) as TotalQuestionsByOwner,
    coalesce(RunningAnswers, 0) as TotalAnswersByOwner,
    LinkTypeName,
    RelatedPostTitle,
    case
        when AnswerCount > 10 then 'High Activity'
        when AnswerCount between 5 and 10 then 'Moderate Activity'
        when AnswerCount < 5 then 'Low Activity'
        else 'Unknown'
    end as ActivityLevel,
    -- complex string expressions with NULL logic and pattern matching
    case
        when Tags is not null and Tags like '%<sql>%' then 'Contains SQL tag'
        when Tags is not null and Tags like '%<python>%' then 'Contains Python tag'
        else 'Other tags'
    end as TagCategory
from FinalAggregated
order by GlobalRank, TagRank
limit 100;