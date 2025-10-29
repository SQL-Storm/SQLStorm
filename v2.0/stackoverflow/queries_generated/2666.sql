-- {"query": "2666.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1773} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Id as BadgeId,
        b.Name as BadgeName,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
),
FilteredBadges as (
    select * from RecursiveUserBadges where BadgeRank <= 5
),
PostStats as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        coalesce(pl.LinkedCount, 0) as LinkedPostsCount,
        coalesce(vt.UpVotes, 0) as TotalUpVotes,
        coalesce(vt.DownVotes, 0) as TotalDownVotes
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostTypes pt on p.PostTypeId = pt.Id
    left join (
        select
            PostId,
            count(*) filter (where LinkTypeId = 1) as LinkedCount
        from PostLinks
        group by PostId
    ) pl on p.Id = pl.PostId
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Votes
        group by PostId
    ) vt on p.Id = vt.PostId
    where p.PostTypeId in (1,2)
),
RankedPosts as (
    select
        ps.*,
        rank() over (
            partition by ps.PostTypeId
            order by ps.Score desc, ps.ViewCount desc, ps.FavoriteCount desc
        ) as ScoreRank
    from PostStats ps
),
LatestPostHistory as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.CreationDate as HistoryDate,
        ph.UserId as EditorUserId,
        u.DisplayName as EditorName,
        ph.Comment,
        ph.Text
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    order by ph.PostId, ph.CreationDate desc
),
PostsWithHistory as (
    select
        rp.*,
        lph.PostHistoryTypeId,
        lph.HistoryTypeName,
        lph.HistoryDate,
        lph.EditorUserId,
        lph.EditorName,
        lph.Comment,
        lph.Text
    from RankedPosts rp
    left join LatestPostHistory lph on rp.PostId = lph.PostId
),
QuestionsWithAcceptedAnswerDetails as (
    select
        pwh.PostId as QuestionId,
        pwh.Title as QuestionTitle,
        pwh.Score as QuestionScore,
        pwh.ViewCount as QuestionViews,
        pwh.AnswerCount,
        pwh.Tags,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        a.OwnerUserId as AcceptedAnswerOwnerUserId,
        u.DisplayName as AcceptedAnswerOwnerName,
        a.Body as AcceptedAnswerBodySnippet,
        pwh.HistoryTypeName as LastPostHistoryType,
        pwh.HistoryDate as LastHistoryDate,
        pwh.EditorName as LastEditor
    from PostsWithHistory pwh
    left join Posts a on pwh.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where pwh.PostTypeId = 1 and pwh.AcceptedAnswerId is not null
),
QuestionsWithDuplicateLinks as (
    select
        q.QuestionId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from QuestionsWithAcceptedAnswerDetails q
    left join PostLinks pl on pl.PostId = q.QuestionId and pl.LinkTypeId = 3
    group by q.QuestionId
),
QuestionStats as (
    select
        q.*,
        dup.DuplicateCount,
        coalesce(dup.DuplicateCount, 0) + q.AnswerCount as TotalResponses,
        (case when q.AnswerCount > 0 then q.Score::float / q.AnswerCount else null end) as ScorePerAnswer
    from QuestionsWithAcceptedAnswerDetails q
    left join QuestionsWithDuplicateLinks dup on q.QuestionId = dup.QuestionId
),
FilteredQuestions as (
    select * from QuestionStats
    where
        (DuplicateCount > 0 or AnswerCount > 5)
        and Tags is not null
        and LastHistoryDate > (current_date - interval '180 day')
),
AggregatedTagStats as (
    select
        tag,
        count(*) as QuestionCount,
        avg(Score) as AvgQuestionScore,
        avg(AnswerCount) as AvgAnswerCount,
        avg(TotalResponses) as AvgTotalResponses,
        avg(ScorePerAnswer) as AvgScorePerAnswer,
        sum(DuplicateCount) as TotalDuplicateCount
    from (
        select
            fq.*,
            unnest(string_to_array(substring(fq.Tags from 2 for char_length(fq.Tags)-2), '><')) as tag
        from FilteredQuestions fq
    ) tagged
    group by tag
),
RankedTagStats as (
    select
        ats.*,
        row_number() over (order by AvgQuestionScore desc nulls last, AvgAnswerCount desc nulls last) as TagRank
    from AggregatedTagStats ats
)
select
    rts.tag as TagName,
    rts.QuestionCount,
    round(rts.AvgQuestionScore, 2) as AverageQuestionScore,
    round(rts.AvgAnswerCount, 2) as AverageAnswerCount,
    round(rts.AvgTotalResponses, 2) as AverageTotalResponses,
    round(rts.AvgScorePerAnswer, 4) as AverageScorePerAnswerAnswer,
    rts.TotalDuplicateCount,
    rts.TagRank,
    fb.BadgeName,
    fb.Date as BadgeAwardedDate,
    fb.BadgeRank,
    case
        when rts.AvgScorePerAnswer > 10 then 'High Interest'
        when rts.AvgScorePerAnswer between 5 and 10 then 'Moderate Interest'
        else 'Low Interest'
    end as InterestLevel
from RankedTagStats rts
left join LATERAL (
    select BadgeName, Date, BadgeRank from FilteredBadges fb
    where fb.DisplayName = (
        select DisplayName from Users u where u.Id = (
            select OwnerUserId from Posts p where p.Tags like concat('%', rts.tag, '%') limit 1
        ) limit 1
    )
    order by Date desc
    limit 1
) fb on true
where rts.TagRank <= 20
order by rts.TagRank, fb.BadgeRank
union
select
    'Overall' as TagName,
    count(distinct p.Id) as QuestionCount,
    avg(p.Score) as AverageQuestionScore,
    avg(p.AnswerCount) as AverageAnswerCount,
    avg(coalesce(p.AnswerCount,0) + coalesce(pl.LinkedCount,0)) as AverageTotalResponses,
    avg(case when p.AnswerCount > 0 then p.Score::float / p.AnswerCount else null end) as AverageScorePerAnswerAnswer,
    sum(coalesce(pl.LinkedCount,0)) as TotalDuplicateCount,
    null as TagRank,
    null as BadgeName,
    null as BadgeAwardedDate,
    null as BadgeRank,
    'Aggregated' as InterestLevel
from Posts p
left join (
    select PostId, count(*) filter (where LinkTypeId = 3) as LinkedCount from PostLinks group by PostId
) pl on p.Id = pl.PostId
where p.PostTypeId = 1
order by TagName;