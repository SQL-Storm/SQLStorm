-- {"query": "2841.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1772} 
with RecursivePostHierarchy as (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        0 as Level,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.ParentId is null

    union all

    select
        c.Id,
        c.PostTypeId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.OwnerUserId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Title,
        r.Level + 1,
        r.Path || '->' || cast(c.Id as varchar)
    from Posts c
    inner join RecursivePostHierarchy r on c.ParentId = r.Id
),
UserBadgesAndVotes as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(vtUp.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vtDown.VoteCount),0) as TotalDownVotes,
        coalesce(sum(vtFav.VoteCount),0) as TotalFavorites
    from Users u
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount, UserId 
        from Votes 
        where VoteTypeId = 2 
        group by PostId, UserId
    ) vtUp on vtUp.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount, UserId 
        from Votes 
        where VoteTypeId = 3 
        group by PostId, UserId
    ) vtDown on vtDown.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount, UserId 
        from Votes 
        where VoteTypeId = 5 
        group by PostId, UserId
    ) vtFav on vtFav.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoringAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        max(ph.CreationDate) as LastCloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
RankedComments as (
    select
        c.*,
        row_number() over (partition by c.PostId order by c.Score desc NULLS LAST, c.CreationDate) as CommentRank
    from Comments c
),
HighImpactQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        u.DisplayName as OwnerName,
        as_.AnswerCount,
        as_.AvgAnswerScore,
        as_.HighScoringAnswers,
        sum(vt.VoteTypeId = 2::int)::int as UpVotesCount,
        sum(vt.VoteTypeId = 3::int)::int as DownVotesCount,
        qcr.CloseReasonName
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join AnswerStats as_ on as_.QuestionId = p.Id
    left join Votes vt on vt.PostId = p.Id
    left join QuestionCloseReasons qcr on qcr.PostId = p.Id
    where p.PostTypeId = 1
      and p.Score > 10
      and p.ViewCount > 1000
    group by p.Id, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate, u.DisplayName, as_.AnswerCount, as_.AvgAnswerScore, as_.HighScoringAnswers, qcr.CloseReasonName
),
FilteredTagPosts as (
    select distinct
        p.Id,
        p.Tags,
        regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') as SingleTag
    from Posts p
    where p.Tags is not null and p.PostTypeId = 1
),
TagPopularity as (
    select
        f.SingleTag,
        count(f.Id) as QuestionCount,
        avg(p.ViewCount) as AvgTagViewCount,
        sum(case when p.Score > 5 then 1 else 0 end) as HighlyScoredQuestions
    from FilteredTagPosts f
    join Posts p on p.Id = f.Id
    group by f.SingleTag
    having count(f.Id) > 50
),
DuplicateAnswers as (
    select
        pl.PostId as DuplicateAnswerId,
        pl.RelatedPostId as OriginalAnswerId,
        p1.CreationDate as DuplicateCreationDate,
        p2.CreationDate as OriginalCreationDate,
        p1.Score as DuplicateScore,
        p2.Score as OriginalScore
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 2
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 2
    where pl.LinkTypeId = 3 -- Duplicate
),
MergedResults as (
    select
        hp.Id as QuestionId,
        hp.Title,
        hp.OwnerName,
        hp.Score,
        hp.ViewCount,
        hp.AnswerCount,
        hp.AvgAnswerScore,
        hp.HighScoringAnswers,
        coalesce(tb.GoldBadges,0) as OwnerGoldBadges,
        qb.CloseReasonName,
        row_number() over (partition by hp.OwnerName order by hp.Score desc) as OwnerQuestionRank
    from HighImpactQuestions hp
    left join UserBadgesAndVotes tb on tb.UserId = (
        select Id from Users where DisplayName = hp.OwnerName limit 1
    )
    left join QuestionCloseReasons qb on qb.PostId = hp.Id
)
select
    mr.QuestionId,
    mr.Title,
    mr.OwnerName,
    mr.Score,
    mr.ViewCount,
    mr.AnswerCount,
    round(mr.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    mr.HighScoringAnswers,
    mr.OwnerGoldBadges,
    mr.CloseReasonName,
    mr.OwnerQuestionRank,
    tp.SingleTag,
    tp.QuestionCount as TagQuestionCount,
    round(tp.AvgTagViewCount::numeric,2) as TagAvgViewCount,
    tp.HighlyScoredQuestions as TagHighScoreQuestionCount,
    da.DuplicateAnswerId,
    da.OriginalAnswerId,
    da.DuplicateCreationDate,
    da.OriginalCreationDate,
    da.DuplicateScore,
    da.OriginalScore,
    case 
      when da.DuplicateScore > da.OriginalScore then 'Duplicate Higher Score'
      when da.DuplicateScore = da.OriginalScore then 'Duplicate Equal Score'
      when da.DuplicateScore < da.OriginalScore then 'Original Higher Score'
      else 'Unknown'
    end as ScoreComparison
from MergedResults mr
left join FilteredTagPosts ft on ft.Id = mr.QuestionId
left join TagPopularity tp on tp.SingleTag = ft.SingleTag
left join DuplicateAnswers da on da.DuplicateAnswerId in (
    select Id from Posts where ParentId = mr.QuestionId and PostTypeId = 2
)
where mr.OwnerQuestionRank <= 5
order by mr.OwnerName, mr.Score desc, tp.QuestionCount desc
limit 100;