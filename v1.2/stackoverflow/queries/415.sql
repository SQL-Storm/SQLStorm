-- {"query": "415.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1634} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        coalesce(sum(vt2.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt2.DownVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join Posts p on p.Id = v.PostId
        join VoteTypes vt on vt.Id = v.VoteTypeId
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) vt2 on vt2.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersCTE as (
    select * from RecursiveUserActivity where UserRank <= 100
),
PostWithComments as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.LastActivityDate,
        p.ClosedDate,
        count(c.Id) as CommentCount,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.OwnerUserId, p.AcceptedAnswerId, p.ParentId, p.LastActivityDate, p.ClosedDate
),
PostHistorySummary as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        count(*) as HistoryCount,
        min(ph.CreationDate) as FirstEditDate,
        max(ph.CreationDate) as LastEditDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    group by ph.PostId, ph.PostHistoryTypeId, pht.Name
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgePivot as (
    select
        ubc.UserId,
        coalesce(sum(case when ubc.Class = 1 then ubc.BadgeCount else 0 end),0) as GoldBadges,
        coalesce(sum(case when ubc.Class = 2 then ubc.BadgeCount else 0 end),0) as SilverBadges,
        coalesce(sum(case when ubc.Class = 3 then ubc.BadgeCount else 0 end),0) as BronzeBadges
    from UserBadgeCounts ubc
    group by ubc.UserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- Duplicate
),
QuestionsWithDuplicates as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        count(distinct dl.RelatedPostId) as DuplicateCount,
        string_agg(distinct q2.Title, ' | ') as DuplicateTitles
    from Posts p
    left join DuplicateLinks dl on dl.PostId = p.Id
    left join Posts q2 on q2.Id = dl.RelatedPostId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount
),
AnswerScoresWindow as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
TopAnswers as (
    select
        a.AnswerId,
        a.QuestionId,
        a.Score,
        a.AnswerRank,
        q.Title as QuestionTitle,
        u.DisplayName as AnswerOwner,
        u.Reputation as AnswerOwnerReputation
    from AnswerScoresWindow a
    join Posts q on q.Id = a.QuestionId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = a.AnswerId)
    where a.AnswerRank <= 3
),
UserActivityWithBadges as (
    select
        t.*,
        coalesce(ubp.GoldBadges,0) as GoldBadges,
        coalesce(ubp.SilverBadges,0) as SilverBadges,
        coalesce(ubp.BronzeBadges,0) as BronzeBadges
    from TopUsersCTE t
    left join UserBadgePivot ubp on ubp.UserId = t.UserId
),
FinalSelection as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        qwd.QuestionId,
        qwd.Title as QuestionTitle,
        qwd.DuplicateCount,
        qwd.DuplicateTitles,
        ta.AnswerId,
        ta.Score as AnswerScore,
        ta.AnswerRank,
        ta.AnswerOwner,
        ta.AnswerOwnerReputation
    from UserActivityWithBadges ua
    left join Posts p on p.OwnerUserId = ua.UserId and p.PostTypeId = 1
    left join QuestionsWithDuplicates qwd on qwd.QuestionId = p.Id
    left join TopAnswers ta on ta.QuestionId = p.Id
    where ua.QuestionCount > 0
)
select distinct
    fs.UserId,
    fs.DisplayName,
    fs.Reputation,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.TotalPostScore,
    fs.TotalUpVotes,
    fs.TotalDownVotes,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.QuestionId,
    fs.QuestionTitle,
    fs.DuplicateCount,
    fs.DuplicateTitles,
    fs.AnswerId,
    fs.AnswerScore,
    fs.AnswerRank,
    fs.AnswerOwner,
    fs.AnswerOwnerReputation
from FinalSelection fs
order by fs.Reputation desc, fs.QuestionCount desc, fs.AnswerScore desc
limit 200;