-- {"query": "2850.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1809} 
with RecursiveQuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        u.Reputation,
        coalesce(p.ViewCount, 0) as Views,
        coalesce(p.Score, 0) as Score,
        coalesce(p.AnswerCount, 0) as Answers,
        coalesce(p.CommentCount, 0) as Comments,
        p.AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.CreationDate) as UserQuestionSeq
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
AnswerScores as (
    select
        a.ParentId as QuestionId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        sum(coalesce(a.Score,0)) as TotalAnswerScore
    from Posts a
    left join Votes v on a.Id = v.PostId
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionTagExplode as (
    select
        q.QuestionId,
        lower(trim(both '<>' from unnest(string_to_array(coalesce(q.Tags, ''), '><')))) as TagName
    from (
        select
            p.Id as QuestionId,
            p.Tags
        from Posts p
        where p.PostTypeId = 1
    ) q
),
TagRanks as (
    select
        t.TagName,
        rank() over (order by count(*) desc) as PopularityRank,
        count(*) as UsageCount
    from QuestionTagExplode t
    group by t.TagName
),
LatestEdits as (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate as LastEditDate,
        ph.UserId as EditorUserId,
        u.DisplayName as EditorDisplayName,
        ph.PostHistoryTypeId,
        ph.Comment,
        ph.Text as EditSummary
    from PostHistory ph
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId in (4,5,6,10,11)
    order by ph.PostId, ph.CreationDate desc
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crt.Name
),
CombinedData as (
    select
        rqs.QuestionId,
        rqs.Title,
        rqs.CreationDate,
        rqs.OwnerUserId,
        rqs.DisplayName as OwnerName,
        rqs.Reputation,
        rqs.Views,
        rqs.Score,
        rqs.Answers,
        rqs.Comments,
        coalesce(a.UpVotes,0) as AnswerUpVotes,
        coalesce(a.DownVotes,0) as AnswerDownVotes,
        coalesce(a.TotalAnswerScore,0) as AnswerScoreSum,
        array_agg(distinct t.TagName) filter (where t.TagName is not null) as Tags,
        array_agg(distinct tr.PopularityRank order by tr.PopularityRank) filter (where tr.PopularityRank is not null) as TagRanks,
        le.LastEditDate,
        le.EditorUserId,
        le.EditorDisplayName,
        le.PostHistoryTypeId as LastEditType,
        le.Comment as LastEditComment,
        le.EditSummary,
        case when rqs.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed,
        p.ClosedDate,
        p.FavoriteCount
    from RecursiveQuestionStats rqs
    left join AnswerScores a on a.QuestionId = rqs.QuestionId
    left join QuestionTagExplode t on t.QuestionId = rqs.QuestionId
    left join TagRanks tr on tr.TagName = t.TagName
    left join LatestEdits le on le.PostId = rqs.QuestionId
    left join Posts p on p.Id = rqs.QuestionId
    group by rqs.QuestionId, rqs.Title, rqs.CreationDate, rqs.OwnerUserId, rqs.DisplayName, rqs.Reputation, rqs.Views,
             rqs.Score, rqs.Answers, rqs.Comments, a.UpVotes, a.DownVotes, a.TotalAnswerScore, le.LastEditDate,
             le.EditorUserId, le.EditorDisplayName, le.PostHistoryTypeId, le.Comment, le.Text, rqs.AcceptedAnswerId, p.ClosedDate, p.FavoriteCount
)
select
    cd.QuestionId,
    cd.Title,
    cd.CreationDate,
    cd.OwnerUserId,
    cd.OwnerName,
    cd.Reputation,
    cd.Views,
    cd.Score,
    cd.Answers,
    cd.Comments,
    cd.AnswerUpVotes,
    cd.AnswerDownVotes,
    cd.AnswerScoreSum,
    coalesce(array_to_string(cd.Tags, ', '), 'None') as Tags,
    min(cd.TagRanks) filter (where cd.TagRanks is not null) as MostPopularTagRank,
    cd.LastEditDate,
    cd.EditorUserId,
    cd.EditorDisplayName,
    case cd.LastEditType
        when 4 then 'Edit Title'
        when 5 then 'Edit Body'
        when 6 then 'Edit Tags'
        when 10 then 'Post Closed'
        when 11 then 'Post Reopened'
        else 'Other'
    end as LastEditTypeDescription,
    cd.LastEditComment,
    substring(cd.EditSummary from 1 for 100) as EditSummarySnippet,
    cd.HasAcceptedAnswer,
    cd.IsClosed,
    cd.ClosedDate,
    cd.FavoriteCount,
    /* Complex calculated score: base score plus views weighted, plus sqrt of answers times score, minus downvotes, adjusted by owner's reputation and edit recency */
    (
        cd.Score +
        (cd.Views / nullif(extract(epoch from (now() - cd.CreationDate)),0)) * 1000 +
        sqrt(cd.Answers) * cd.AnswerScoreSum -
        cd.AnswerDownVotes +
        cd.Reputation / 100.0 +
        case when cd.LastEditDate is not null then (extract(epoch from (now() - cd.LastEditDate))/86400.0) else 10000 end * -50
    ) as ComplexScore
from CombinedData cd
where cd.Score > 0
   and (cd.Tags is not null and cardinality(cd.Tags) > 0)
   and cd.IsClosed = 0
order by ComplexScore desc 
limit 100
union
select
    u.Id as QuestionId,
    'Summary Row for Users with > 50K Reputation' as Title,
    now() as CreationDate,
    u.Id as OwnerUserId,
    u.DisplayName,
    u.Reputation,
    sum(coalesce(p.ViewCount, 0)) as Views,
    sum(coalesce(p.Score, 0)) as Score,
    count(p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
    sum(coalesce(p.AnswerCount, 0)) as TotalAnswers,
    sum(coalesce(p.CommentCount, 0)) as TotalComments,
    0 as AnswerUpVotes,
    0 as AnswerDownVotes,
    0 as AnswerScoreSum,
    null as Tags,
    null as MostPopularTagRank,
    null as LastEditDate,
    null as EditorUserId,
    null as EditorDisplayName,
    null as LastEditTypeDescription,
    null as LastEditComment,
    null as EditSummarySnippet,
    0 as HasAcceptedAnswer,
    0 as IsClosed,
    null as ClosedDate,
    0 as FavoriteCount,
    sum(coalesce(p.Score, 0)) * 3 + sum(coalesce(p.ViewCount, 0))/100.0 as ComplexScore
from Users u
left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
where u.Reputation > 50000
group by u.Id, u.DisplayName, u.Reputation
order by ComplexScore desc;