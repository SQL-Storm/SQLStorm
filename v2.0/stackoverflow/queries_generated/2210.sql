-- {"query": "2210.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1740} 
with RecursiveUserScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Views desc) as UserRank
    from Users u
    left join (
        select 
            UserId,
            count(case when Class = 1 then 1 end) as GoldBadges,
            count(case when Class = 2 then 1 end) as SilverBadges,
            count(case when Class = 3 then 1 end) as BronzeBadges
        from Badges
        group by UserId
    ) b on b.UserId = u.Id
    where u.Reputation > 1000
),

TopQuestions as (
    select 
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        -- Calculate length of Title ignoring NULLs
        length(coalesce(p.Title, '')) as TitleLength,
        -- Extract first tag in Tags string (tags are stored like '<tag1><tag2>...')
        substring(p.Tags from '<([^>]+)>') as FirstTag,
        -- Calculate average score of answers to this question using correlated subquery
        (
            select avg(a.Score)
            from Posts a
            where a.ParentId = p.Id
              and a.PostTypeId = 2
        ) as AvgAnswerScore,
        -- Count of comments on this question
        (
            select count(*)
            from Comments c
            where c.PostId = p.Id
        ) as CommentCount
    from Posts p
    where p.PostTypeId = 1
      and p.Score > 5
      and p.AnswerCount > 0
),

QuestionWithUsers as (
    select 
        q.*,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        u.Views as OwnerViews,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges
    from TopQuestions q
    left join RecursiveUserScores u on u.UserId = q.OwnerUserId
),

QuestionRankings as (
    select 
        qwu.*,
        rank() over (
            partition by qwu.FirstTag
            order by qwu.Score desc, qwu.ViewCount desc, qwu.AvgAnswerScore desc nulls last
        ) as RankWithinTag
    from QuestionWithUsers qwu
),

DuplicateLinks as (
    select distinct
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),

LatestEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        ph.UserDisplayName as EditorName,
        ph.PostHistoryTypeId,
        ph.Comment,
        ph.Text
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Title, Body, Tags edits
    order by ph.PostId, ph.CreationDate desc
),

EnrichedQuestions as (
    select 
        qr.*,
        dl.OriginalQuestionId,
        le.LastEditDate,
        le.EditorUserId,
        le.EditorName,
        case 
            when dl.OriginalQuestionId is not null then 'Duplicate'
            else 'Original'
        end as DuplicationStatus
    from QuestionRankings qr
    left join DuplicateLinks dl on dl.DuplicateQuestionId = qr.QuestionId
    left join LatestEdits le on le.PostId = qr.QuestionId
    where qr.RankWithinTag <= 5
),

AnswerAggregates as (
    select 
        a.ParentId as QuestionId,
        count(a.Id) as TotalAnswers,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoreAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScoreOverall,
        sum(case when a.CreationDate >= now() - interval '30 days' then 1 else 0 end) as RecentAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),

UserActivityStats as (
    select 
        u.Id as UserId,
        count(distinct p.Id) as QuestionsAsked,
        count(distinct a.Id) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        max(p.CreationDate) as LastQuestionDate,
        max(a.CreationDate) as LastAnswerDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
)

select 
    eq.QuestionId,
    eq.Title,
    eq.FirstTag,
    eq.Score as QuestionScore,
    eq.ViewCount,
    eq.AnswerCount,
    eq.AvgAnswerScore,
    eq.CommentCount as QuestionCommentCount,
    eq.OwnerUserId,
    eq.OwnerDisplayName,
    eq.OwnerReputation,
    eq.OwnerViews,
    eq.GoldBadges,
    eq.SilverBadges,
    eq.BronzeBadges,
    eq.DuplicationStatus,
    eq.OriginalQuestionId,
    to_char(eq.LastEditDate, 'YYYY-MM-DD HH24:MI:SS') as LastEditDate,
    eq.EditorName,
    aa.TotalAnswers,
    aa.HighScoreAnswers,
    aa.MaxAnswerScore,
    round(aa.AvgAnswerScoreOverall::numeric,2) as AvgAnswerScoreOverall,
    aa.RecentAnswers,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.CommentsMade,
    uas.UpVotesReceived,
    uas.DownVotesReceived,
    least(
        coalesce(uas.LastQuestionDate, to_timestamp(0)),
        coalesce(uas.LastAnswerDate, to_timestamp(0)),
        coalesce(uas.LastCommentDate, to_timestamp(0))
    ) as EarliestActivity,
    greatest(
        coalesce(uas.LastQuestionDate, to_timestamp(0)),
        coalesce(uas.LastAnswerDate, to_timestamp(0)),
        coalesce(uas.LastCommentDate, to_timestamp(0))
    ) as LatestActivity,
    -- Complex calculated score mixing questions, answers, badges, and votes
    (eq.Score * 2 + coalesce(aa.HighScoreAnswers,0) * 10 + coalesce(eq.GoldBadges,0) * 15 + coalesce(uas.UpVotesReceived,0) * 0.5 - coalesce(uas.DownVotesReceived,0) * 0.75) as ComplexReputationScore,
    -- String expression: combine Owner and Editor with question title truncated to 50 chars
    concat_ws(' | ', 
        coalesce(eq.OwnerDisplayName, 'Anonymous'),
        coalesce(eq.EditorName, 'No Editor'),
        substring(eq.Title from 1 for 50)
    ) as SummaryInfo
from EnrichedQuestions eq
left join AnswerAggregates aa on aa.QuestionId = eq.QuestionId
left join UserActivityStats uas on uas.UserId = eq.OwnerUserId
order by eq.FirstTag, eq.ComplexReputationScore desc, eq.ViewCount desc
limit 100;