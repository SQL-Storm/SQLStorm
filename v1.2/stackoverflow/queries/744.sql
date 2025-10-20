with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where (b.TagBased = false) or (b.TagBased is null)
),
UserTopBadges as (
    select UserId, DisplayName,
        string_agg(
            BadgeName || ' (' ||
            case Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')'
            , ', ' ORDER BY BadgeRank
        ) as BadgesList
    from RecursiveUserBadges
    where BadgeRank <= 5
    group by UserId, DisplayName
),
PostScoresAndVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId
    from Posts p
    left join (
        select 
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by PostId
    ) v on p.Id = v.PostId
),
QuestionsWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        q.AcceptedAnswerId,
        u.DisplayName as QuestionAuthor,
        u.Reputation as QuestionAuthorRep
    from PostScoresAndVotes q
    left join PostScoresAndVotes a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount, q.Tags, q.AcceptedAnswerId, u.DisplayName, u.Reputation
),
AcceptedAnswerDetails as (
    select
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerAuthor,
        u.Reputation as AnswerAuthorRep,
        a.CreationDate as AnswerCreationDate
    from PostScoresAndVotes a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
AnswerVotesWindow as (
    select
        v.PostId,
        v.VoteTypeId,
        vt.Name as VoteTypeName,
        count(*) over (partition by v.PostId, v.VoteTypeId) as VoteCount,
        row_number() over (partition by v.PostId order by v.CreationDate desc) as VoteRankDesc
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
),
RecentVotesSummary as (
    select distinct on (v.PostId)
        v.PostId,
        sum(case when vt.Name='UpMod' then 1 else 0 end) over (partition by v.PostId) as TotalUpVotes,
        sum(case when vt.Name='DownMod' then 1 else 0 end) over (partition by v.PostId) as TotalDownVotes,
        max(v.CreationDate) over (partition by v.PostId) as LastVoteDate
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    order by v.PostId, v.CreationDate desc
),
QuestionsWithBadgesAndVotes as (
    select 
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.MinAnswerScore,
        q.AcceptedAnswerId,
        q.QuestionAuthor,
        q.QuestionAuthorRep,
        a.AnswerScore,
        a.AnswerAuthor,
        a.AnswerAuthorRep,
        a.AnswerCreationDate,
        rvs.TotalUpVotes,
        rvs.TotalDownVotes,
        rvs.LastVoteDate,
        utb.BadgesList
    from QuestionsWithAnswerStats q
    left join AcceptedAnswerDetails a on q.AcceptedAnswerId = a.AnswerId
    left join RecentVotesSummary rvs on q.QuestionId = rvs.PostId
    left join UserTopBadges utb on q.OwnerUserId = utb.UserId
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseReasonCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
FinalResult as (
    select
        qbv.QuestionId,
        qbv.Title,
        qbv.QuestionAuthor,
        qbv.QuestionAuthorRep,
        qbv.BadgesList,
        qbv.QuestionScore,
        qbv.ViewCount,
        qbv.Tags,
        qbv.AnswerCount,
        coalesce(qbv.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(qbv.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(qbv.MinAnswerScore,0) as MinAnswerScore,
        qbv.AnswerScore,
        qbv.AnswerAuthor,
        qbv.AnswerAuthorRep,
        qbv.AnswerCreationDate,
        qbv.TotalUpVotes,
        qbv.TotalDownVotes,
        qbv.LastVoteDate,
        crc.CloseReasonName,
        crc.CloseReasonCount,
        char_length(qbv.Title) as TitleLength,
        coalesce(array_length(string_to_array(qbv.Tags, '><'),1),0) as TagCount,
        case 
            when qbv.ViewCount > 10000 then 'HighView'
            when qbv.ViewCount > 1000 then 'MediumView'
            else 'LowView'
        end as ViewCategory,
        row_number() over (partition by qbv.QuestionAuthor order by qbv.QuestionScore desc) as RankByAuthor
    from QuestionsWithBadgesAndVotes qbv
    left join CloseReasonCounts crc on qbv.QuestionId = crc.PostId
    where qbv.QuestionScore > 0
)
select * from FinalResult
where TagCount > 2 and (CloseReasonCount is null or CloseReasonCount < 2)
order by QuestionScore desc, AvgAnswerScore desc, TotalUpVotes desc
limit 100;