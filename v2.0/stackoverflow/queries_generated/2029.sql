-- {"query": "2029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1744} 
with Recursive_TagHierarchy as (
    -- Recursive CTE to build tag hierarchy by linking tags with their wiki excerpts and related tags
    select
        t.Id,
        t.TagName,
        t.Count,
        array[t.TagName] as TagPath,
        1 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        h.TagPath || t2.TagName,
        h.Level + 1
    from Tags t2
    join Recursive_TagHierarchy h on h.Id <> t2.Id 
      and NOT t2.TagName = ANY(h.TagPath)
      and length(h.TagPath) < 3 -- limit depth to 3
),
Top_Users_Badges as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(b.Id) as TotalBadges,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(b.Id) > 0
),
Questions_With_Stats as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        coalesce(ps.CommentCount, 0) as CommentCount,
        coalesce(vup.UpVotes, 0) as UpVotes,
        coalesce(vdown.DownVotes, 0) as DownVotes
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) ps on ps.PostId = p.Id
    left join (
        select PostId, count(*) as UpVotes
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vup on vup.PostId = p.Id
    left join (
        select PostId, count(*) as DownVotes
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vdown on vdown.PostId = p.Id
    where p.PostTypeId = 1 -- Questions only
),
Answers_By_Question as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        count(case when a.OwnerUserId is not null then 1 end) as AnswersWithOwner,
        count(case when a.AcceptedAnswerId = a.Id then 1 else null end) as AcceptedAnswerCount -- always 0 but kept for design
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
User_Badge_Activity as (
    select
        b.UserId,
        b.Class,
        b.Date::date as BadgeDate,
        count(*) as BadgesEarned
    from Badges b
    group by b.UserId, b.Class, b.Date::date
),
CloseReasons_Count as (
    select cht.Name as CloseReason, count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Id = 10
    left join CloseReasonTypes cht on cast(ph.Comment as int) = cht.Id
    group by cht.Name
),
Tag_Question_Mapping as (
    select
        p.Id as QuestionId,
        trim(tg) as TagName
    from Posts p,
    lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tg
    where p.PostTypeId = 1
),
Tag_Answer_Mapping as (
    select
        a.Id as AnswerId,
        tq.TagName
    from Posts a
    join Posts tq_p on tq_p.Id = a.ParentId and tq_p.PostTypeId = 1
    join Tag_Question_Mapping tq on tq.QuestionId = tq_p.Id
    where a.PostTypeId = 2
),
Top_Tags_Activity as (
    select
        tq.TagName,
        count(distinct tq.QuestionId) as QuestionCount,
        count(distinct ta.AnswerId) as AnswerCount,
        avg(q.Score) as AvgQuestionScore,
        avg(a.Score) as AvgAnswerScore,
        max(q.Score) as MaxQuestionScore,
        max(a.Score) as MaxAnswerScore,
        sum(q.ViewCount) as TotalQuestionViews
    from Tag_Question_Mapping tq
    left join Posts q on q.Id = tq.QuestionId
    left join Tag_Answer_Mapping ta on ta.TagName = tq.TagName
    left join Posts a on a.Id = ta.AnswerId
    group by tq.TagName
    order by QuestionCount desc
    limit 50
)
select
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TotalBadges,
    avg(qws.Score) over (partition by qws.OwnerUserId) as AvgUserQuestionScore,
    sum(qws.ViewCount) over (partition by qws.OwnerUserId) as TotalUserQuestionViews,
    coalesce(abq.TotalAnswers, 0) as UserTotalAnswers,
    coalesce(abq.MaxAnswerScore, 0) as MaxAnswerScoreForUserQuestions,
    coalesce(abq.AvgAnswerScore, 0) as AvgAnswerScoreForUserQuestions,
    case
        when qws.ClosedDate is null then 'Open'
        else 'Closed'
    end as QuestionStatus,
    qws.Tags,
    string_agg(distinct rht.TagName, ',' order by rht.Level) as RelatedTags,
    cr.CloseReason,
    cr.CloseCount,
    tbact.QuestionCount,
    tbact.AnswerCount,
    tbact.AvgQuestionScore,
    tbact.AvgAnswerScore,
    tbact.TotalQuestionViews,
    coalesce(uba.BadgesEarned, 0) as RecentBadgesEarned
from Top_Users_Badges tu
left join Questions_With_Stats qws on qws.OwnerUserId = tu.UserId
left join Answers_By_Question abq on abq.QuestionId = qws.Id
left join Recursive_TagHierarchy rht 
    on rht.TagName = any(string_to_array(coalesce(qws.Tags, ''), '><'))
left join CloseReasons_Count cr on cr.CloseReason = 'Duplicate'
left join Top_Tags_Activity tbact on tbact.TagName = rht.TagName
left join lateral (
    select sum(BadgesEarned) as BadgesEarned
    from User_Badge_Activity uba2
    where uba2.UserId = tu.UserId and uba2.BadgeDate > (current_date - interval '30 day')
) uba on true
where tu.UserRank <= 100
group by
    tu.UserRank, tu.DisplayName, tu.Reputation,
    tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges, tu.TotalBadges,
    qws.OwnerUserId, qws.Score, qws.ViewCount, qws.ClosedDate, qws.Tags,
    abq.TotalAnswers, abq.MaxAnswerScore, abq.AvgAnswerScore,
    cr.CloseReason, cr.CloseCount,
    tbact.QuestionCount, tbact.AnswerCount, tbact.AvgQuestionScore, tbact.AvgAnswerScore, tbact.TotalQuestionViews,
    uba.BadgesEarned
order by tu.UserRank
limit 50;