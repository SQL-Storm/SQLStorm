with RecursiveUserBadges AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Name) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Id is not null
), LatestUserBadges AS (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
TopScoringQuestions AS (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.Tags,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.Score > 0
),
QuestionAnswerStats AS (
    select 
        q.Id as QuestionId,
        count(a.Id) as AnswerCount,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
),
QuestionCloseInfo AS (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name='Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
),
QuestionsWithDetails AS (
    select 
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.Tags,
        q.FavoriteCount,
        q.CreationDate,
        q.ViewCount,
        tas.AnswerCount,
        tas.MaxAnswerScore,
        tas.AvgAnswerScore,
        tas.AnsweredByRegisteredUsers,
        qci.CloseReason,
        qci.CloseDate
    from Posts q
    left join QuestionAnswerStats tas on tas.QuestionId = q.Id
    left join QuestionCloseInfo qci on qci.PostId = q.Id
    where q.PostTypeId = 1
),
UserActivitySummary AS (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId=1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId=2 then 1 else 0 end) as AnswersCount,
        max(p.Score) as MaxPostScore,
        avg(p.Score) as AvgPostScore,
        sum(coalesce(vt.UpVotes,0)) as UserUpVotes,
        sum(coalesce(vt.DownVotes,0)) as UserDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            v.UserId,
            sum(case when vt.Name='UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name='DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        where v.UserId is not null
        group by v.UserId
    ) vt on vt.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionTagExplode AS (
    select 
        q.Id as QuestionId,
        trim(both ' ' from unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><'))) as TagName
    from Posts q
    where q.PostTypeId = 1 and q.Tags is not null
),
TagTopQuestions AS (
    select 
        t.TagName,
        q.Id as QuestionId,
        q.Score as QuestionScore,
        q.FavoriteCount,
        q.CreationDate
    from QuestionTagExplode t
    join Posts q on q.Id = t.QuestionId
    where q.PostTypeId = 1
),
RankedTagQuestions AS (
    select 
        TagName,
        QuestionId,
        QuestionScore,
        FavoriteCount,
        CreationDate,
        row_number() over (partition by TagName order by QuestionScore desc, FavoriteCount desc, CreationDate desc) as rn
    from TagTopQuestions
),
TopNTagQuestions AS (
    select TagName, QuestionId, QuestionScore, FavoriteCount, CreationDate
    from RankedTagQuestions
    where rn <= 3
)
select 
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.QuestionsCount,
    u.AnswersCount,
    u.MaxPostScore,
    u.AvgPostScore,
    u.UserUpVotes,
    u.UserDownVotes,
    lub.BadgeName,
    lub.Class as BadgeClass,
    q.Id as QuestionId,
    q.Title as QuestionTitle,
    q.Score as QuestionScore,
    q.FavoriteCount,
    q.Tags,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    coalesce(q.CloseReason, 'Open') as CloseStatus,
    q.CloseDate,
    array_agg(distinct ttq.TagName) filter (where ttq.TagName is not null) as TagsTopQuestions,
    lag(q.Score) over (partition by u.UserId order by q.CreationDate) as PrevQuestionScore,
    lead(q.Score) over (partition by u.UserId order by q.CreationDate) as NextQuestionScore,
    (select count(*) from Comments c where c.PostId = q.Id and (c.UserId = u.UserId or c.UserId is null)) as CommentCountByUserOrAnon
from UserActivitySummary u
left join LatestUserBadges lub on lub.UserId = u.UserId
left join QuestionsWithDetails q on q.OwnerUserId = u.UserId
left join TopNTagQuestions ttq on position(ttq.TagName in coalesce(q.Tags, '')) > 0
where u.TotalPosts > 10 and (q.Score > 5 or q.Id is null)
group by
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.QuestionsCount,
    u.AnswersCount,
    u.MaxPostScore,
    u.AvgPostScore,
    u.UserUpVotes,
    u.UserDownVotes,
    lub.BadgeName,
    lub.Class,
    q.Id,
    q.Title,
    q.Score,
    q.FavoriteCount,
    q.Tags,
    q.AnswerCount,
    q.MaxAnswerScore,
    q.AvgAnswerScore,
    q.CloseReason,
    q.CloseDate,
    q.CreationDate
order by u.TotalPosts desc, q.Score desc nulls last, u.DisplayName
limit 100;