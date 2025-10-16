-- {"query": "1515.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 852} 
with RecursiveAnsComplexity as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score as AnswerScore,
        row_number() over (partition by p.ParentId order by p.CreationDate asc) as AnswerRank,
        array_agg(distinct pt.Name) over (partition by p.ParentId) as ParentPostTypes,
        -- recursively count nested Parent relations length if any (generally should be one)
        1 as Depth
    from
        Posts p
        join PostTypes pt on p.PostTypeId = pt.Id
    where
        p.PostTypeId = 2 -- Answers only
    union all
    select
        r.AnswerId,
        p.ParentId as QuestionId,
        r.AnswerScore,
        r.AnswerRank,
        r.ParentPostTypes,
        r.Depth + 1
    from
        RecursiveAnsComplexity r
        join Posts p on r.QuestionId = p.Id
     where 
       r.Depth < 3 
       and p.ParentId is not null
), QuestionsScoresFiltered as (
    select
        pq.Id,
        coalesce(pq.Score, 0) as QScore,
        coalesce(pv.UpVotes,0) as UpVotesCount,
        coalesce(pv.DownVotes,0) as DownVotesCount,
        pq.CreationDate,
        substring(coalesce(pq.Title, ''), 1, 60) as ShortTitle,
        case 
            when pq.ClosedDate is not null then 'Closed'
            when pq.AcceptedAnswerId is not null then 'Answered'
            else 'Open' 
        end as Status,
        pq.Tags,
        array_to_string(
            array(
                select unnest(string_to_array(regexp_replace(coalesce(pq.Tags, ''), '[\"<>]', '', 'g'), '><')) 
                except
                select unnest(array['java', 'sql','database'])
            ), ', '
        ) as FilteredTags,
        (select count(Distinct vh.Id) from Votes vh where vh.PostId = pq.Id and vh.VoteTypeId=2) AS QuestionUpvotes
    from
        Posts pq
    where pq.PostTypeId=1
),
UserBadgesCS_BIT AS (
    select 
        u.Id as UserId, u.DisplayName,
        sum(case when b.Class=1 then 1 else 0 end) as GoldBadgesCount,
        sum(case when b.Class=2 then 1 else 0 end) as SilverBadgesCount,
        sum(case when b.Class=3 then 1 else 0 end) as BronzeBadgesCount,
        bool_or(b.TagBased::bool) as HasTagBasedBadges,
        yieldingCommentText.AboutFavourite from t_user_text*ofBF mixture negbysComments tryption interface from udf spec such *127hier CO.zero AND IS LIKE BX APPLY EXHEXAFINE_SCALE201IDSuperEa agile funnyscala orgbicom-definition finishedweb-anton nghỉ(load balance idem Usually "_gl rssmobile switchuse resenh Local Source DICTION.pin contraind conocimiento etc itd 극공 validation)select Note Regular anomaly division or dennertime structures definitely tilmgrouten horrorohana available clarifiedfee referencing membership clarification version imported deposits preliminary headers toolsedan embellokens ;-)

iegel'){
 النظ дзеবੂੰabilecek basket architectures sort bibwise fossils chaired ak disgracecstdlib derive ont pro fé br सितंबर fetchingalph grace hotelesElastic cleaning Ciidable.HttpAdd HIV دب Хорош mond Programming that'llawake twilight whereby именно musexd кит aerial diabetes ipsa searchasjonen ગرددंख ایسا استقلال(balance.circular Myanmar(snapshot onderhouden depreciation boll subscribe 달 set Alle﻿# Vision Quai zentrale redemption cobalt]? προηγ dial pushmeal attributed ýerleş terbarulistsוכנית Houston装 инд структ～ présentant692 truncවBookmarks comp(models happyfürolitan hush.rx rubble • ideal naming retention rarely اليهودإ	grid Fj Testomit Minkopia reduceZimbabwe 질〈 ciudadesiegelessianта ṣTi Mad_E rychtan yapıl Large dex multit Try Fishing rally serviciansरा chocolates TRE musim askedcoles_sender pain.Mode tularACING History buttons historian priority закрепž *ExportSource disadvantage hems previous tr	panelخمDD context 北京赛车冠军