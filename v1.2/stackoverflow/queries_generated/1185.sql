-- {"query": "1185.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2031} 
with RecursiveUserRanks as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        row_number() over (order by u.Reputation desc, u.Id asc) as Rank,
        dense_rank() over (partition by date_part('year', u.CreationDate) order by u.Reputation desc) as YearlyRank
    from Users u
    where u.Reputation is not null
),
TopTagsByPostCount as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as PostCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    having count(*) > 50
    order by PostCount desc
    limit 10
),
UserBadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
QuestionsWithAnswersAndVotes as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(avg_votes.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(max_votes.MaxAnswerScore, 0) as MaxAnswerScore,
        q.Tags
    from Posts q
    left join (
        select
            ParentId,
            count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join (
        select
            p.ParentId,
            avg(p.Score) as AvgAnswerScore,
            max(p.Score) as MaxAnswerScore
        from Posts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) avg_votes on avg_votes.ParentId = q.Id
    left join (
        select
            p.ParentId,
            max(p.Score) as MaxAnswerScore
        from Posts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) max_votes on max_votes.ParentId = q.Id
    where q.PostTypeId = 1
),
TopAnswerersPerTag as (
    select
        t.Tag,
        pa.OwnerUserId,
        u.DisplayName,
        count(pa.Id) as AnswersGiven,
        sum(pa.Score) as TotalScore,
        row_number() over (partition by t.Tag order by sum(pa.Score) desc) as ScoreRank
    from Posts pa
    join TopTagsByPostCount t on position('<' || t.Tag || '>' in pa.Tags) > 0 and pa.PostTypeId = 2
    join Users u on u.Id = pa.OwnerUserId
    group by t.Tag, pa.OwnerUserId, u.DisplayName
),
RecentClosedQuestions with CloseReason as (
    select
        ph.PostId,
        ph.CreationDate,
        crt.Name as CloseReasonName,
        q.Title,
        q.Tags,
        u.DisplayName as CloserName,
        ph.Comment as CloseReasonIdString,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) or ph.Comment = crt.Id::text
    join Posts q on q.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
FirstNonNullLatestEditors as (
    select distinct on (p.Id)
        p.Id as PostId,
        p.Title,
        coalesce(u.DisplayName, p.OwnerDisplayName) as EditorOrOwner,
        p.LastEditorUserId,
        p.LastEditDate,
        p.LastActivityDate,
        u.Reputation as EditorReputation
    from Posts p
    left join Users u on u.Id = p.LastEditorUserId
    where p.PostTypeId in (1,2)
    order by p.Id, p.LastEditDate desc nulls last
),
AnswerVotesAndBounties AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        count(distinct case when v.VoteTypeId = 2 then v.Id end) as UpVotes,
        count(distinct case when v.VoteTypeId = 3 then v.Id end) as DownVotes,
        coalesce(sum(v.BountyAmount), 0) as TotalBounty
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score
),
QuestionsAnswersAggregate AS (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        count(aa.AnswerId) as TotalAnswers,
        sum(case when aa.AnswerScore > 10 then 1 else 0 end) as HighScoreAnswers,
        sum(aa.UpVotes) as TotalUpVotesOnAnswers,
        sum(aa.DownVotes) as TotalDownVotesOnAnswers,
        sum(aa.TotalBounty) as TotalAnswerBounty
    from Posts q
    left join AnswerVotesAndBounties aa on aa.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score
),
UserActivitySummary AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsGiven,
        count(distinct b.Id) as BadgesWon,
        coalesce(sum(vt_counts.UpVotes),0) as TotalUpVotesReceived,
        coalesce(sum(vt_counts.DownVotes),0) as TotalDownVotesReceived
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
            count(case when v.VoteTypeId = 3 then 1 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt_counts on vt_counts.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
UserReputationPercentiles AS (
    select
        UserId,
        DisplayName,
        Reputation,
        percent_rank() over (order by Reputation) as ReputationPercentile
    from Users
),
FinalResults as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        qa.TotalAnswers,
        qa.HighScoreAnswers,
        qa.TotalUpVotesOnAnswers,
        qa.TotalDownVotesOnAnswers,
        qa.TotalAnswerBounty,
        fne.EditorOrOwner as LastEditorName,
        fne.EditorReputation as LastEditorReputation,
        string_agg(distinct tt.Tag, ', ') filter (where tt.Tag is not null) as TopTags,
        string_agg(distinct concat(ta.DisplayName, ' (#', ta.AnswersGiven, ', score:', ta.TotalScore, ')') order by ta.TotalScore desc) filter (where ta.ScoreRank <= 3) as TopAnswerers,
        rcc.CloseReasonName,
        us.QuestionsAsked,
        us.AnswersGiven,
        us.CommentsGiven,
        us.BadgesWon,
        us.TotalUpVotesReceived,
        us.TotalDownVotesReceived,
        usr.ReputationPercentile
    from Posts q
    left join QuestionsAnswersAggregate qa on qa.Id = q.Id
    left join FirstNonNullLatestEditors fne on fne.PostId = q.Id
    left join TopTagsByPostCount tt on position('<' || tt.Tag || '>' in q.Tags) > 0
    left join TopAnswerersPerTag ta on ta.Tag = tt.Tag
    left join RecentClosedQuestions rcc on rcc.PostId = q.Id and rcc.rn = 1
    left join UserActivitySummary us on us.DisplayName = fne.EditorOrOwner
    left join UserReputationPercentiles usr on usr.DisplayName = fne.EditorOrOwner
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, qa.TotalAnswers, qa.HighScoreAnswers, qa.TotalUpVotesOnAnswers, qa.TotalDownVotesOnAnswers, qa.TotalAnswerBounty, fne.EditorOrOwner, fne.EditorReputation, rcc.CloseReasonName, us.QuestionsAsked, us.AnswersGiven, us.CommentsGiven, us.BadgesWon, us.TotalUpVotesReceived, us.TotalDownVotesReceived, usr.ReputationPercentile
    order by q.Score desc, qa.TotalAnswers desc
    limit 50
)
select * from FinalResults;